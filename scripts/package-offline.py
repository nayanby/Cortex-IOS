"""Build a private offline bundle, optionally inject into an unsigned device IPA."""
import argparse, hashlib, json, re, shutil, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

def note_order(path):
    match=re.match(r"^([IVXLCDM]+)\.",path.stem)
    if match:
        values={"I":1,"V":5,"X":10,"L":50,"C":100,"D":500,"M":1000}
        numeral=match[1]
        number=sum(-values[c] if i+1<len(numeral) and values[c]<values[numeral[i+1]] else values[c] for i,c in enumerate(numeral))
        return (path.parent.as_posix().casefold(),0,number,path.name.casefold())
    return (path.parent.as_posix().casefold(),1,0,path.name.casefold())

def build(source, output):
    output.mkdir(parents=True, exist_ok=True)
    notes=[]; entries=[]; warnings=[]; card_keys=set(); bundle_files=[]; originals={}
    ns={"w":"http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    for p in sorted((p for p in (source/"files").rglob("*") if p.is_file() and not p.name.startswith("~$") and p.suffix.lower() in {".docx", ".dotx"}),key=note_order):
        relative=p.relative_to(source/"files").as_posix()
        digest=hashlib.sha256(relative.encode()).hexdigest()
        name=digest+".docx"
        shutil.copy2(p,output/name);bundle_files.append(output/name)
        headings=[]
        with zipfile.ZipFile(p) as z:
            root=ET.fromstring(z.read("word/document.xml"))
            for para in root.findall(".//w:body//w:p",ns):
                style=para.find("w:pPr/w:pStyle",ns)
                value=style.get("{"+ns["w"]+"}val","") if style is not None else ""
                match=re.fullmatch(r"(?:Heading|heading)([1-4])",value)
                if match:
                    text="".join(t.text or "" for t in para.findall(".//w:t",ns)).strip()
                    if text: headings.append({"level":int(match[1]),"text":text})
        notes.append(dict(id=digest,path=relative,subject=p.parent.name if p.parent!=source/"files" else "Unfiled",displayName=p.stem,fileName=p.name,sizeBytes=p.stat().st_size,storagePath="files/"+relative,sortOrder=len(notes),headings=headings))
    counts={}
    for kind,folder in [("Snapshots","Snapshots"),("Flashcards","flashcards"),("Qbank","Qbank")]:
        files=sorted([p for p in (source/folder).rglob("*") if p.is_file()],key=lambda p:(p.name!="flashcards.json",str(p)))
        for p in files:
            original=p.relative_to(source).as_posix()
            short="raw/"+hashlib.sha256(original.encode()).hexdigest()[:24]+".bin"
            if short in originals and originals[short]!=original:raise ValueError("Raw content identifier collision")
            originals[short]=original
            dest=output/short
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest);bundle_files.append(dest)
            if p.suffix.lower()!=".json": continue
            try: v=json.loads(p.read_text(encoding="utf-8-sig"))
            except (ValueError, UnicodeError):
                warnings.append(str(p.relative_to(source))); continue
            if kind=="Snapshots":
                for item in v.get("posters",[]):
                    payload=item.get("payload",{}); data=payload.get("data",{})
                    if data.get("sections"):
                        entries.append(dict(kind=kind,document=v.get("document",""),folder=v.get("folder",""),title=payload.get("scope",{}).get("scopeLabel") or data.get("title","Snapshot"),data=data))
            elif kind=="Qbank" and isinstance(v.get("questions"),list) and v["questions"]:
                entries.append(dict(kind=kind,document=v.get("document",""),folder=v.get("folder",""),title=v.get("headingText") or v.get("document","Qbank"),data={"questions":v["questions"]}))
            elif kind=="Flashcards" and p.name=="flashcards.json":
                for deck in v.get("decks",[]):
                    card_keys.add(deck.get("key"))
                    entries.append(dict(kind=kind,document=deck.get("documentName",""),folder=deck.get("folderName",""),title=deck.get("scopeLabel") or deck.get("documentName","Flashcards"),data=deck.get("data",{})))
            elif kind=="Flashcards" and v.get("data",{}).get("cards"):
                key=v.get("key") or v.get("documentKey",v.get("recordKey",""))+"::"+v.get("scope",{}).get("scopeKey","")
                if key not in card_keys:
                    card_keys.add(key)
                    entries.append(dict(kind=kind,document=v.get("source",{}).get("fileName",p.parent.name).removesuffix(".docx"),folder=v.get("source",{}).get("folderName",p.parent.parent.name),title=v.get("scope",{}).get("scopeLabel",p.stem),data=v["data"]))
        counts[kind]=len(files)
    for i,e in enumerate(entries):
        e["id"]=hashlib.sha256(json.dumps([e["kind"],e["folder"],e["document"],e["title"],e["data"]],sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        data=e.pop("data")
        e["content"]=data

    entries=list({entry["id"]:entry for entry in entries}.values())
    (output/"catalog.json").write_text(json.dumps({"notes":notes},ensure_ascii=False),encoding="utf-8")
    (output/"study.json").write_text(json.dumps(entries,ensure_ascii=False),encoding="utf-8")
    (output/"import-warnings.json").write_text(json.dumps(warnings),encoding="utf-8")
    (output/"source-files.json").write_text(json.dumps(originals,ensure_ascii=False),encoding="utf-8")
    bundle_files += [output/name for name in ["catalog.json","study.json","import-warnings.json","source-files.json"]]
    print(json.dumps({"warnings":warnings,"notes":len(notes),"headings":sum(len(n["headings"]) for n in notes),"studyEntries":len(entries),"sourceFiles":counts}))

    return bundle_files

def main():
    p=argparse.ArgumentParser();p.add_argument("--source",type=Path,required=True);p.add_argument("--output",type=Path,default=Path("build/OfflineLibrary"));p.add_argument("--ipa",type=Path);p.add_argument("--output-ipa",type=Path)
    a=p.parse_args();bundle_files=build(a.source,a.output)
    if a.ipa:
        if not a.output_ipa or a.ipa.resolve()==a.output_ipa.resolve():p.error("Choose a distinct --output-ipa")
        with zipfile.ZipFile(a.ipa) as src,zipfile.ZipFile(a.output_ipa,"w",zipfile.ZIP_DEFLATED) as dst:
            for info in src.infolist():
                if "/OfflineLibrary/" not in info.filename:dst.writestr(info,src.read(info))
            for f in bundle_files:
                dst.write(f,"Payload/Cortex.app/OfflineLibrary/"+f.relative_to(a.output).as_posix())
        print("Private offline IPA created; sign with iPASide before installation.")
if __name__=="__main__":main()
