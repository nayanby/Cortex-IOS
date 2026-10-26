const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'Cortex/Resources/library_catalog.json'), 'utf8'));
assert.ok(Array.isArray(catalog.notes) && catalog.notes.length, 'Catalog must contain notes');
const ids = new Set();
const paths = new Set();
let headingCount = 0;
for (const note of catalog.notes) {
  for (const key of ['id', 'path', 'subject', 'displayName', 'fileName', 'storagePath']) {
    assert.equal(typeof note[key], 'string', `${note.id}: ${key} must be a string`);
    assert.ok(note[key].trim(), `${note.id}: ${key} is empty`);
  }
  assert.ok(!ids.has(note.id), `Duplicate note ID: ${note.id}`);
  assert.ok(!paths.has(note.path.toLowerCase()), `Duplicate document path: ${note.path}`);
  assert.ok(Number.isSafeInteger(note.sizeBytes) && note.sizeBytes >= 0, `Invalid size: ${note.id}`);
  assert.ok(Number.isSafeInteger(note.sortOrder), `Invalid ordering: ${note.id}`);
  assert.ok(!note.path.split('/').includes('..'), `Invalid document path: ${note.id}`);
  ids.add(note.id);
  paths.add(note.path.toLowerCase());
  for (const heading of note.headings ?? []) {
    assert.ok(Number.isInteger(heading.level), `Invalid heading level: ${note.id}`);
    assert.equal(typeof heading.text, 'string', `Invalid heading text: ${note.id}`);
    for (const key of ['flash', 'quiz', 'snapshot']) {
      assert.ok(heading[key] == null || typeof heading[key] === 'boolean', `Invalid ${key}: ${note.id}`);
    }
    headingCount++;
  }
}
for (const suffix of ['regular', 'bold', 'italic', 'bold_italic']) {
  assert.ok(fs.statSync(path.join(root, `Cortex/Resources/averia_serif_libre_${suffix}.ttf`)).size > 1000);
}
console.log(`Catalog valid: ${ids.size} chapters, ${new Set(catalog.notes.map(n => n.subject)).size} subjects, ${headingCount} headings; four fonts present.`);
