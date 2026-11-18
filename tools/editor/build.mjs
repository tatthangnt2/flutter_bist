// Writes the build into ../../bin: editor.html (with bist.ts embedded – opens with a double click), bist.mjs (command line),
// bist.d.ts (types for VS Code). Run through `npm run build` (after tsc compiled bist.ts into out/).
// `--check` builds into a temp folder and fails when bin/ differs from the sources (used by CI: someone forgot to build).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const bin = path.resolve(here, '..', '..', 'bin');
const check = process.argv.includes('--check');
const outDir = check ? fs.mkdtempSync(path.join(os.tmpdir(), 'bist-build-')) : bin;
fs.mkdirSync(outDir, { recursive: true });

const src = fs.readFileSync(path.join(here, 'bist.ts'), 'utf8');
if (/<\/script/i.test(src)) throw new Error('bist.ts must not contain a closing script tag');
const html = fs.readFileSync(path.join(here, 'editor.html'), 'utf8');
const slot = /(<script id="bist-src" type="text\/plain">)[\s\S]*?(<\/script>)/;
if (!slot.test(html)) throw new Error('editor.html is missing <script id="bist-src" type="text/plain"></script>');

const files = {
  'editor.html': html.replace(slot, (_, a, b) => a + src + b),
  'bist.mjs': fs.readFileSync(path.join(here, 'out', 'bist.js'), 'utf8'),
  'bist.d.ts': fs.readFileSync(path.join(here, 'out', 'bist.d.ts'), 'utf8'),
};

let stale = [];
for (const [name, text] of Object.entries(files)) {
  fs.writeFileSync(path.join(outDir, name), text);
  if (check) {
    const cur = path.join(bin, name);
    if (!fs.existsSync(cur) || fs.readFileSync(cur, 'utf8') !== text) stale.push(`bin/${name}`);
  }
}
if (check) {
  fs.rmSync(outDir, { recursive: true, force: true });
  if (stale.length) {
    console.error(`Out of date: ${stale.join(', ')} – run \`npm run build\` in tools/editor and commit bin/`);
    process.exit(1);
  }
  console.log('bin/ is up to date');
} else {
  console.log(`Built ${Object.keys(files).map((f) => `bin/${f}`).join(', ')}`);
}
