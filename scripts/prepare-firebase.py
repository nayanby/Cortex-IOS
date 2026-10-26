"""Prepare optional CI config and the Google callback scheme without logging keys."""
import os
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def validate(fields):
    if fields.get("PROJECT_ID") != "cortex-v1b" or fields.get("BUNDLE_ID") != "com.cortex.notes":
        raise ValueError("Firebase project or bundle ID does not match CORTEX iOS")
    if not str(fields.get("GOOGLE_APP_ID", "")).startswith("1:302875225635:ios:"):
        raise ValueError("Configuration must belong to the registered Apple app")
    if not fields.get("API_KEY"):
        raise ValueError("Firebase configuration is incomplete")
    scheme = fields.get("REVERSED_CLIENT_ID", "")
    if scheme and (not scheme.startswith("com.googleusercontent.apps.") or not all(c.isalnum() or c in ".-" for c in scheme)):
        raise ValueError("Invalid Google callback scheme")
    return scheme


def main():
    directory = ROOT / "Config"
    directory.mkdir(exist_ok=True)
    target = directory / "GoogleService-Info.plist"
    supplied = os.environ.get("CORTEX_FIREBASE_PLIST", "")
    if supplied:
        fields = plistlib.loads(supplied.encode("utf-8"))
        validate(fields)
        target.write_bytes(plistlib.dumps(fields))
        target.chmod(0o600)
    scheme = "com.cortex.notes.unconfigured"
    if target.exists():
        scheme = validate(plistlib.loads(target.read_bytes())) or scheme
        print("Validated local Firebase Apple configuration.")
    else:
        print("No live Firebase config supplied; building offline preview and emulator tests.")
    (directory / "Firebase.generated.xcconfig").write_text(
        "// Generated locally; contains only the Google callback scheme.\n"
        f"CORTEX_GOOGLE_URL_SCHEME = {scheme}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
