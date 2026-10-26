// Synthetic data for a demo project, never the production Firebase project.
const fs = require('node:fs');
const path = require('node:path');
const bytes = fs.readFileSync(path.join(__dirname, '../CortexTests/Fixtures/reader-check.docx'));
const project = 'demo-cortex-ios';
async function checked(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) throw new Error(`Emulator seed failed (${response.status}): ${await response.text()}`);
}
(async () => {
  await checked('http://127.0.0.1:9199/v0/b/demo-cortex-ios.appspot.com/o?uploadType=media&name=files%2FTests%2Freader-check.docx', {
    method:'POST', headers:{Authorization:'Bearer owner', 'Content-Type':'application/vnd.openxmlformats-officedocument.wordprocessingml.document'}, body:bytes
  });
  const strings = {fileName:'reader-check.docx', subject:'Tests', path:'Tests/reader-check.docx',
    displayName:'Reader integration check', storagePath:'files/Tests/reader-check.docx', etag:'fixture-v1'};
  const fields = Object.fromEntries(Object.entries(strings).map(([k,v])=>[k,{stringValue:v}]));
  fields.sizeBytes = {integerValue:String(bytes.length)};
  fields.sortOrder = {integerValue:'0'};
  await checked(`http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/library/catalog/notes/test-note`, {
    method:'PATCH', headers:{Authorization:'Bearer owner','Content-Type':'application/json'}, body:JSON.stringify({fields})
  });
  console.log('Seeded synthetic DOCX and catalog in local demo emulators.');
})();
