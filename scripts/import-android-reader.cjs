// Re-extract only the renderer, without app state, accounts, AI settings or notes.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const source = path.resolve(process.argv[2] || '../Cortex Consumer 2/app');
const target = path.resolve(__dirname, '../Cortex/Resources/Reader');
fs.mkdirSync(path.join(target, 'fonts'), {recursive:true});
const html = fs.readFileSync(path.join(source, 'build/generated/assets/slimReleasePage/index.html'), 'utf8');
const begin = html.indexOf('const NS = {');
const end = html.indexOf('\nlet activeDocumentId = null;', begin);
if (begin < 0 || end < 0) throw new Error('Android renderer boundaries changed; review the extraction.');
const renderer = html.slice(begin, end);
if (!renderer.includes('class DocxPrototype') || /EMBEDDED_APP_STATE|EMBEDDED_LIBRARY/.test(renderer)) {
  throw new Error('Renderer extraction is incomplete or contains app state');
}
const formula = fs.readFileSync(path.join(source, 'page-formula-omml.js'), 'utf8');
const script = `// Extracted from Cortex Consumer; see android-reader-provenance.json.\n${renderer}\n${formula}\nwindow.CortexDocx = DocxPrototype;\nwindow.cortexReleaseImages = revokeObjectUrls;\n`;
new vm.Script(script);
fs.writeFileSync(path.join(target, 'docx-renderer.js'), script);
const styles = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map(m=>m[1]).join('\n');
fs.writeFileSync(path.join(target, 'android-reader.css'), styles);
let overrides = fs.readFileSync(path.join(source, 'src/main/assets/native-overrides.css'), 'utf8');
overrides = overrides.replaceAll('/assets/fonts/', 'fonts/');
fs.writeFileSync(path.join(target, 'native-overrides.css'), overrides);
const fonts = [...new Set([...overrides.matchAll(/url\(['"]?fonts\/([^)'"\s]+)/g)].map(m=>m[1]))];
for (const font of fonts) fs.copyFileSync(path.join(source, 'src/main/assets/fonts', font), path.join(target, 'fonts', font));
for (const name of ['jszip.min.js', 'viewer-typography.js']) {
  fs.copyFileSync(path.join(source, 'src/main/assets', name), path.join(target, name));
}
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
for (const [original, destination] of [
  ['src/main/assets/fonts/OFL.txt', 'fonts/SourceSansPro-OFL.txt'],
  ['src/main/assets/fonts/noto_serif-OFL.txt', 'fonts/NotoSerif-OFL.txt'],
  ['src/main/res/raw/averia_serif_libre_license.txt', 'fonts/AveriaSerifLibre-OFL.txt']
]) fs.copyFileSync(path.join(source, original), path.join(target, destination));
fs.writeFileSync(path.join(target, 'android-reader-provenance.json'), JSON.stringify({
  androidVersion: '1.0.22', sourceHTMLSHA256: hash(html), rendererSHA256: hash(script),
  scope: 'DocxPrototype with XML helpers, formula patch, page styles, native overrides, typography and offline dependencies. No embedded app state.',
  fontFiles: fonts
}, null, 2)+'\n');
console.log(`Extracted renderer and ${fonts.length} offline fonts.`);
