"""Wrap a downloaded GitHub simulator artifact for Appetize; optionally add local preview DOCX files.

Content stays outside source control. This script never fetches credentials or uploads files.
"""
import argparse
import json
import pathlib
import plistlib
import stat
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("artifact", type=pathlib.Path)
parser.add_argument("output", type=pathlib.Path)
parser.add_argument("--notes-dir", type=pathlib.Path)
parser.add_argument("--allow-configured-build", action="store_true")
args = parser.parse_args()

with zipfile.ZipFile(args.artifact) as source:
    names = source.namelist()
    prefix = "Cortex.app/" if "Cortex.app/Info.plist" in names else ""
    info = plistlib.loads(source.read(prefix + "Info.plist"))
    if info.get("CFBundleIdentifier") != "com.cortex.notes":
        raise SystemExit("Expected the CORTEX iOS app.")
    if not args.allow_configured_build and any("GoogleService-Info.plist" in n for n in names):
        raise SystemExit("This build contains Firebase client configuration; authorize its destination before packaging.")
    files = {}
    for entry in source.infolist():
        if entry.is_dir():
            continue
        name = entry.filename.removeprefix(prefix)
        if name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts:
            raise SystemExit("Unsafe archive path.")
        files[name] = source.read(entry)

manifest = {}
if args.notes_dir:
    catalog = json.loads(files["library_catalog.json"])
    for note in catalog["notes"]:
        path = args.notes_dir / pathlib.Path(note["fileName"]).name
        if not path.is_file():
            continue
        data = path.read_bytes()
        if not data.startswith(b"PK\x03\x04") or len(data) > 32 * 1024 * 1024:
            raise SystemExit("Preview note is not a supported DOCX file.")
        # A stable, ASCII filename also avoids special characters in bundle URLs.
        name = f"note-{len(manifest)}.docx"
        files["PreviewNotes/" + name] = data
        manifest[note["id"]] = name
    if not manifest:
        raise SystemExit("No local preview files matched the bundled catalog.")
    files["preview-library.json"] = json.dumps(manifest).encode()

args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as output:
    for name, data in files.items():
        item = zipfile.ZipInfo("Cortex.app/" + name)
        item.create_system = 3
        item.compress_type = zipfile.ZIP_DEFLATED
        mode = 0o755 if name == "Cortex" or name.endswith(".dylib") else 0o644
        item.external_attr = (stat.S_IFREG | mode) << 16
        output.writestr(item, data)
with zipfile.ZipFile(args.output) as check:
    if check.testzip() is not None:
        raise SystemExit("Archive validation failed.")
print(f"Prepared {args.output.resolve()} with {len(manifest)} actual preview note(s).")
