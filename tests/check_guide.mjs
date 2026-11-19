// Node harness for the guide. Each Roc sample must appear, its lines in order and
// ignoring indentation and blank lines, in one file that the suite compiles: an
// example, a template of ./joy init, or a file in guide/samples/, which exists for
// this. A sample that cannot compile, like two rival definitions shown side by
// side, says so with Doc.sketch. A walk-through's lines and excerpts (see
// guide/Walk.roc) are samples too.
// The in-page links of the built guide must lead somewhere too.
// Run from the repo root, after guide/build.roc: node tests/check_guide.mjs
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from './harness.mjs';

// The samples of one topic. The text is a Roc multiline string, whose `\$` is `$`.
const samplesOf = (topic) => {
  const lines = readFileSync(`guide/Topic/${topic}.roc`, 'utf8').split('\n');
  const found = [];
  lines.forEach((line, at) => {
    const call = /(Doc\.code|Doc\.sketch|Walk\.lines|Walk\.excerpt)\(\s*$/.exec(line);
    if (!call) return;
    let next = at + 1;
    while (!/^\s*\\\\/.test(lines[next])) next++;
    const before = lines.slice(at + 1, next).map((l) => l.trim().replace(/,$/, ''));
    // Walk.lines takes the steps it is lit in, and is always Roc. Only a Doc block names a file.
    const lang = call[1] === 'Walk.lines' ? 'Roc' : before[0];
    const file = call[1].startsWith('Doc.') ? before[1] : '';
    const text = [];
    for (; /^\s*\\\\/.test(lines[next]); next++) text.push(lines[next].replace(/^\s*\\\\ ?/, '').replaceAll('\\$', '$'));
    found.push({ where: `${topic}:${at + 1}`, kind: call[1] === 'Doc.sketch' ? 'sketch' : 'code', lang, file: file.replaceAll('"', ''), text });
  });
  return found;
};
const topics = readdirSync('guide/Topic').map((name) => name.replace(/\.roc$/, ''));
const samples = topics.flatMap(samplesOf);

// So a change to how the topics write samples cannot leave this checking nothing.
const inTopics = topics.map((t) => readFileSync(`guide/Topic/${t}.roc`, 'utf8').split(/(?:Doc\.code|Doc\.sketch|Walk\.lines|Walk\.excerpt)\(/).length - 1).reduce((a, b) => a + b, 0);
expect('guide: every sample was found', samples.length, inTopics);
expect('guide: there are samples', samples.length > 50, true);

const skipped = new Set(['node_modules', 'build', 'dist', 'www', '.joy', 'e2e', 'tests', 'generated']);
const rocFiles = (dir) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  if (statSync(path).isDirectory()) return skipped.has(name) ? [] : rocFiles(path);
  return name.endsWith('.roc') ? [path] : [];
});
const significant = (lines) => lines.map((l) => l.trim()).filter((l) => l !== '');
// A release's URL is not known here, so a platform's name stands for any platform,
// on a line of its own or in a header written on one line.
const anyPlatform = (line) => line.replace(/pf: platform "[^"]*"/, 'pf: platform "*"');
const corpus = [...rocFiles('examples'), ...rocFiles('guide/samples')].map((path) => ({ path, lines: significant(readFileSync(path, 'utf8').split('\n')) }));

// The lines of `sample` that `file` lacks, in order, once those before them matched.
const missing = (sample, file) => {
  let from = 0;
  const lacked = [];
  for (const line of sample) {
    const at = file.lines.findIndex((l, i) => i >= from && (l === line || anyPlatform(l) === anyPlatform(line)));
    if (at < 0) lacked.push(line);
    else from = at + 1;
  }
  return lacked;
};

for (const s of samples.filter((x) => x.lang === 'Roc' && x.kind === 'code')) {
  const need = significant(s.text);
  const tried = corpus.map((file) => ({ file, lacked: missing(need, file) })).sort((a, b) => a.lacked.length - b.lacked.length);
  const best = tried[0];
  expect(`guide: ${s.where} is in code that compiles`, best.lacked.length === 0 ? 'found' : `closest is ${best.file.path}, which lacks:\n${best.lacked.join('\n')}`, 'found');
}

// --- Links ---
if (existsSync('guide/www/index.html')) {
  const html = readFileSync('guide/www/index.html', 'utf8');
  const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
  const links = [...html.matchAll(/href="#([^"]+)"/g)].map((m) => decodeURIComponent(m[1]));
  expect('guide: there are in-page links', links.length > 20, true);
  expect('guide: every in-page link leads somewhere', [...new Set(links)].filter((id) => !ids.has(id)).join(' '), '');
} else {
  expect('guide: built, for its links', 'guide/www/index.html is missing, run guide/build.roc', 'built');
}
