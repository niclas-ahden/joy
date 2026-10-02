// Node harness for namespaces: SVG and MathML built by the client get the
// namespace and the names the HTML parser would give the same markup, on the
// first render, through every patch that builds nodes (REPLACE, REORDER NEW,
// a lazy region), and under hydration. The fake DOM records each element's
// namespace and stores foreign attributes under their adjusted names (see
// fakedom.mjs), so these checks pin that the runtime asks for the right
// namespace everywhere. tests/e2e/hydrate_parity_test.roc holds the same
// trees against a real parser.
// Run from the repo root: JOY_OPT=speed node tests/check_svg.mjs
import { readFileSync } from 'node:fs';
import { mount, childNamespace, foreignAttr, foreignTagName, NS } from '../www/runtime.js';
import { El, Text, byClass, fakeDom, html } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('svg'));

// --- The tables, as pure functions ---

expect('svg under html', childNamespace('html', '', 'svg'), 'svg');
expect('math under html', childNamespace('html', '', 'math'), 'math');
expect('an uppercase SVG still opens svg', childNamespace('html', '', 'SVG'), 'svg');
expect('anything under svg stays svg', childNamespace('svg', 'g', 'div'), 'svg');
expect('foreignObject hands its children back to html', childNamespace('svg', 'foreignobject', 'div'), 'html');
expect('desc hands its children back to html', childNamespace('svg', 'desc', 'span'), 'html');
expect('svg title hands its children back to html', childNamespace('svg', 'title', 'b'), 'html');
expect('svg inside foreignObject opens svg again', childNamespace('svg', 'foreignobject', 'svg'), 'svg');
expect('MathML text elements hand back to html', childNamespace('math', 'mi', 'span'), 'html');
expect('but keep mglyph in math', childNamespace('math', 'mi', 'mglyph'), 'math');
expect('and malignmark', childNamespace('math', 'mtext', 'malignmark'), 'math');
expect('mrow keeps math', childNamespace('math', 'mrow', 'mi'), 'math');
expect('annotation-xml carrying html', childNamespace('math', 'annotation-xml', 'div', 'text/html'), 'html');
expect('annotation-xml carrying xhtml', childNamespace('math', 'annotation-xml', 'div', 'application/xhtml+xml'), 'html');
expect('annotation-xml opens svg', childNamespace('math', 'annotation-xml', 'svg'), 'svg');
expect('annotation-xml keeps other children math', childNamespace('math', 'annotation-xml', 'mi'), 'math');

expect('svg tag case fixed', foreignTagName('svg', 'lineargradient'), 'linearGradient');
expect('svg tag case fixed from any case', foreignTagName('svg', 'FEGAUSSIANBLUR'), 'feGaussianBlur');
expect('other svg tags lowercased', foreignTagName('svg', 'Circle'), 'circle');
expect('math tags lowercased', foreignTagName('math', 'MI'), 'mi');
expect('svg attr case fixed', JSON.stringify(foreignAttr('svg', 'viewbox')), '{"name":"viewBox","ns":null}');
expect('svg attr already right', JSON.stringify(foreignAttr('svg', 'viewBox')), '{"name":"viewBox","ns":null}');
expect('plain svg attrs lowercased', JSON.stringify(foreignAttr('svg', 'Stroke-Width')), '{"name":"stroke-width","ns":null}');
expect('xlink:href in the xlink namespace', JSON.stringify(foreignAttr('svg', 'xlink:href')), JSON.stringify({ name: 'xlink:href', ns: NS.xlink }));
expect('xml:lang in the xml namespace', foreignAttr('math', 'xml:lang').ns, NS.xml);
expect('xmlns in the xmlns namespace', foreignAttr('svg', 'xmlns').ns, NS.xmlns);
expect('MathML definitionURL', foreignAttr('math', 'definitionurl').name, 'definitionURL');
expect('the svg table is not applied to math', foreignAttr('math', 'viewbox').name, 'viewbox');

// --- A client build ---

// Every element under `node` as ns:tag, for whole-tree namespace checks.
const nsList = (node, out = []) => {
  for (const c of node.children) {
    if (c instanceof El) {
      out.push(`${c.ns}:${c.tag}`);
      nsList(c, out);
    }
  }
  return out;
};
const svgOf = (root) => byClass(root, 'canvas');
const icons = (root) => byClass(root, 'icons');

async function fresh() {
  const root = new El('#root');
  const app = await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
  return { root, app };
}

const { root } = await fresh();
const svg = svgOf(root);
const click = (r, cls) => byClass(r, cls).listeners.click();

expect('the buttons are html', byClass(root, 'shape').ns, 'html');
expect('the svg is svg', `${svg.ns}:${svg.tag}`, 'svg:svg');
expect('viewbox was stored as viewBox', svg.attrs.get('viewBox'), '0 0 100 100');
expect('no lowercase viewbox left behind', svg.attrs.has('viewbox'), false);
const defs = svg.children[0];
expect('lineargradient became linearGradient', `${defs.children[0].ns}:${defs.children[0].tag}`, 'svg:linearGradient');
expect('stop is svg', defs.children[0].children[0].ns, 'svg');
expect('stop-color kept its name', defs.children[0].children[0].attrs.get('stop-color'), 'red');
expect('symbol and its circle are svg', nsList(defs.children[1]).join(' '), 'svg:circle');
const use = byClass(root, 'sprite');
expect('use is svg', use.ns, 'svg');
expect('plain href is a plain attribute', use.attrNs.has('href'), false);
expect('xlink:href is in the xlink namespace', use.attrNs.get('xlink:href'), NS.xlink);
const fo = svg.children[3];
expect('foreignobject became foreignObject', `${fo.ns}:${fo.tag}`, 'svg:foreignObject');
expect('the div inside foreignObject is html', byClass(root, 'inside-fo').ns, 'html');
expect('desc is svg, its span html', `${svg.children[4].ns} ${byClass(root, 'in-desc').ns}`, 'svg html');
expect('the icons and their titles are svg', nsList(icons(root)).join(' '), 'svg:g svg:title svg:circle svg:g svg:title svg:circle');
expect('the lazy label is svg', byClass(root, 'label').ns, 'svg');

// --- Patches that build nodes ---

const circle = byClass(root, 'shape');
click(root, 'shape');
const rect = svgOf(root).children[1];
expect('the swapped shape is a new node', rect !== circle, true);
expect('REPLACE under svg builds svg', `${rect.ns}:${rect.tag}`, 'svg:rect');
click(root, 'shape');
expect('and back again', `${svgOf(root).children[1].ns}:${svgOf(root).children[1].tag}`, 'svg:circle');
expect('with its attributes', svgOf(root).children[1].attrs.get('fill'), 'url(#grad)');

click(root, 'add');
click(root, 'add');
expect('NEW keyed icons are svg', nsList(icons(root)).filter((s) => !s.startsWith('svg:')).length, 0);
expect('four icons now', icons(root).children.length, 4);
const before = icons(root).children.map((g) => g.attrs.get('data-name')).join(',');
click(root, 'rotate');
const after = icons(root).children.map((g) => g.attrs.get('data-name')).join(',');
expect('rotate moved the first icon last', `${before} -> ${after}`, 'a,b,n0,n1 -> b,n0,n1,a');
expect('moved icons stay svg', nsList(icons(root)).filter((s) => !s.startsWith('svg:')).length, 0);

click(root, 'relabel');
expect('the lazy region re-rendered in svg', `${byClass(root, 'label').ns} ${byClass(root, 'label').children[0].text}`, 'svg first+');

// --- MathML, swapped in under an html parent ---

click(root, 'math');
const math = byClass(root, 'formula');
expect('math is MathML', `${math.ns}:${math.tag}`, 'math:math');
expect('the whole formula', nsList(math).join(' '),
  'math:mi html:span math:mglyph math:mrow math:mo math:mn math:annotation-xml html:div math:annotation-xml svg:svg');
click(root, 'math');
expect('math off leaves no formula', byClass(root, 'formula'), null);
click(root, 'math');
expect('math on again is MathML again', byClass(root, 'formula').ns, 'math');

// --- Hydration ---

// A server-rendered copy of a client build, the way the parser hands it
// over: same namespaces and names, adjacent text merged, empty text gone.
function parsedClone(node) {
  if (node instanceof Text) return new Text(node.text);
  const el = new El(node.tag, node.ns);
  for (const [k, v] of node.attrs) el.attrs.set(k, v);
  for (const [k, v] of node.attrNs) el.attrNs.set(k, v);
  let pending = null;
  for (const c of node.children) {
    if (c instanceof Text) { pending = (pending ?? '') + c.text; continue; }
    if (pending) fakeDom.append(el, new Text(pending));
    pending = null;
    fakeDom.append(el, parsedClone(c));
  }
  if (pending) fakeDom.append(el, new Text(pending));
  return el;
}
const stage = (from) => {
  const r = new El('#root');
  for (const c of from.children) fakeDom.append(r, parsedClone(c));
  return r;
};
async function hydrateOver(staged) {
  const warns = [];
  const realWarn = console.warn;
  console.warn = (...a) => warns.push(a.join(' '));
  try {
    const app = await mount({ wasm: bytes, root: staged, flags: '', dom: fakeDom, hydrate: true });
    return { app, warns };
  } finally {
    console.warn = realWarn;
  }
}

{
  const { root: plain } = await fresh();
  const staged = stage(plain);
  const ssrSvg = svgOf(staged);
  const ssrUse = byClass(staged, 'sprite');
  const { app, warns } = await hydrateOver(staged);
  expect('svg markup claims cleanly', JSON.stringify(app.hydration()), '{"claimed":true,"mismatch":null}');
  expect('no warning', warns.length, 0);
  expect('the svg was claimed, not rebuilt', svgOf(staged) === ssrSvg, true);
  expect('the use was claimed with its xlink:href', `${byClass(staged, 'sprite') === ssrUse} ${ssrUse.attrNs.get('xlink:href')}`, `true ${NS.xlink}`);
  expect('claimed page equals the client build', html(staged), html(plain));
  click(staged, 'shape');
  expect('a patch after the claim builds svg', `${svgOf(staged).children[1].ns}:${svgOf(staged).children[1].tag}`, 'svg:rect');
  click(staged, 'add');
  expect('a NEW icon after the claim is svg', nsList(icons(staged)).filter((s) => !s.startsWith('svg:')).length, 0);
  click(staged, 'math');
  expect('math after the claim is MathML', nsList(byClass(staged, 'formula')).join(' ').startsWith('math:mi html:span math:mglyph'), true);
}

{
  // Stale markup: the server rendered the square while the app starts on the
  // circle. The repair builds the circle fresh, in svg.
  const { root: other } = await fresh();
  click(other, 'shape');
  const staged = stage(other);
  const { app, warns } = await hydrateOver(staged);
  const shape = svgOf(staged).children[1];
  expect('the stale shape is reported', app.hydration().mismatch, 'expected <circle> but the server rendered <rect>');
  expect('one warning', warns.length, 1);
  expect('the repaired circle is svg', `${shape.ns}:${shape.tag}`, 'svg:circle');
  const { root: ref } = await fresh();
  expect('repaired page equals the client build', html(staged), html(ref));
}

{
  // The parser put a title in the html namespace (a view that nests
  // differently than it renders would do this): same tag, wrong namespace,
  // so it is rebuilt rather than claimed.
  const { root: plain } = await fresh();
  const staged = stage(plain);
  const g = icons(staged).children[0];
  const htmlTitle = new El('title', 'html');
  fakeDom.append(htmlTitle, new Text('a'));
  g.children[0] = htmlTitle;
  htmlTitle.parent = g;
  const { app } = await hydrateOver(staged);
  expect('the namespace mismatch is reported', app.hydration().mismatch, 'expected <title> in the svg namespace but the server\'s <title> is in the html one');
  expect('the title was rebuilt in svg', `${icons(staged).children[0].children[0].ns} ${icons(staged).children[0].children[0] !== htmlTitle}`, 'svg true');
}

{
  // A lowercase viewbox in markup the parser never saw (a hand-written
  // shell, say) is not the attribute the view declares: the claim rewrites
  // it to viewBox and reports the stray one.
  const { root: plain } = await fresh();
  const staged = stage(plain);
  const s = svgOf(staged);
  s.attrs.delete('viewBox');
  s.attrs.set('viewbox', '0 0 100 100');
  const { app } = await hydrateOver(staged);
  expect('viewBox restored', s.attrs.get('viewBox'), '0 0 100 100');
  expect('stray lowercase viewbox swept', s.attrs.has('viewbox'), false);
  expect('and reported in the spelling the view uses',app.hydration().mismatch, 'expected viewbox="0 0 100 100" on <svg> but the server rendered no viewbox');
}
