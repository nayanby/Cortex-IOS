const fs = require('node:fs');
const path = require('node:path');
const JSZip = require('../Cortex/Resources/Reader/jszip.min.js');
(async () => {
  const zip = new JSZip();
  zip.file('[Content_Types].xml', `<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>`);
  zip.file('word/styles.xml', `<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style></w:styles>`);
  zip.file('word/document.xml', `<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Reader integration check</w:t></w:r></w:p>
    <w:p><w:r><w:t xml:space="preserve">Safe text: &lt;script&gt;window.injected=true&lt;/script&gt; &amp; apostrophe's</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table header</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Table value</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    <w:p><m:oMath><m:r><m:t>eGFR = 90</m:t></m:r></m:oMath></w:p>
    </w:body></w:document>`);
  const dir = path.resolve(__dirname, '../CortexTests/Fixtures');
  fs.mkdirSync(dir, {recursive:true});
  fs.writeFileSync(path.join(dir, 'reader-check.docx'), await zip.generateAsync({type:'nodebuffer', compression:'DEFLATE'}));
})();
