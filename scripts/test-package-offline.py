import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location("pack",Path(__file__).with_name("package-offline.py"))
pack=importlib.util.module_from_spec(spec);spec.loader.exec_module(pack)

class OfflinePackagingTests(unittest.TestCase):
    def test_catalog_content_order_deduplication_and_empty_source_report(self):
        workspace=Path(__file__).resolve().parent.parent
        temporary_root=workspace/"build"
        temporary_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as directory:
            base=Path(directory).resolve()
            assert base.is_relative_to(workspace)
            source=base/"source";output=base/"bundle"
            for folder in ["files/Cardiology","Snapshots","flashcards","Qbank"]:(source/folder).mkdir(parents=True)
            xml='<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Example heading</w:t></w:r></w:p></w:body></w:document>'
            for name in ["IX. Nine.docx","V. Five.docx","Template.dotx"]:
                with zipfile.ZipFile(source/"files/Cardiology"/name,"w") as archive:archive.writestr("word/document.xml",xml)
            (source/"flashcards/empty.json").write_text("")
            question={"folder":"Cardiology","document":"V. Five","headingText":"Topic","questions":[{"question":"Q","options":["A","B"],"correctIndex":0,"explanation":"E"}]}
            for name in ["first.json","duplicate.json"]:(source/"Qbank"/name).write_text(json.dumps(question))
            (source/"Qbank/stats.json").write_text('{"questions":10}')
            with contextlib.redirect_stdout(io.StringIO()):pack.build(source,output)
            notes=json.loads((output/"catalog.json").read_text())["notes"]
            self.assertEqual([n["displayName"] for n in notes],["V. Five","IX. Nine","Template"])
            self.assertEqual(notes[0]["headings"][0]["text"],"Example heading")
            for note in notes:self.assertEqual((output/(note["id"]+".docx")).read_bytes(),(source/"files"/note["path"]).read_bytes())
            self.assertEqual(len(json.loads((output/"study.json").read_text())),1)
            self.assertEqual(len(json.loads((output/"import-warnings.json").read_text())),1)
            self.assertTrue((output/"data/flashcards/empty.json").exists())
if __name__=="__main__":unittest.main()
