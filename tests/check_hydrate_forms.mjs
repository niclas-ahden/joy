// Node harness for form controls under hydration: the state HTML expresses
// differently than a view declares it (a textarea's value is its text, a
// select ignores a value attribute), and the state a user gives the
// server-rendered controls before the app boots, which the claim keeps and
// then delivers to the app through the controls' own handlers.
// Run from the repo root: JOY_OPT=speed node tests/check_hydrate_forms.mjs
import { readFileSync } from 'node:fs';
import { mount } from '../www/runtime.js';
import { El, Text, byClass, fakeDom, html, textOf } from './fakedom.mjs';
import { expect, wasmPath } from './harness.mjs';

const bytes = readFileSync(wasmPath('hydrate_forms'));

const el = (tag, attrs, children) => {
  const n = new El(tag);
  for (const [k, v] of Object.entries(attrs)) fakeDom.setAttr(n, k, v);
  for (const c of children) fakeDom.append(n, c);
  return n;
};
const tx = (s) => new Text(s);
const echoOf = (m) => `${m.name}|${m.bio}|${m.notes}|${m.size}|${m.level}|${m.color}|${m.agree ? 'yes' : 'no'}`;

// The fixture's view as the parser hands it over. `bioAs` picks how the
// server wrote the value-attribute textarea: 'text' as its content (what
// joy-html writes), 'attr' as a value attribute HTML ignores (what older
// joy-html wrote). A select's value attribute is put on the node directly,
// since the parser keeps it as a plain attribute that sets nothing.
function ssrDom(m, { bioAs = 'text', bioText = m.bio, name = m.name } = {}) {
  const level = el('select', { class: 'level' }, ['low', 'high'].map((v) => el('option', { value: v }, [tx(v)])));
  level.attrs.set('value', m.level);
  const radio = (v) => el('input', { class: v, type: 'radio', name: 'color', value: v, ...(m.color === v ? { checked: '' } : {}) }, []);
  return el('div', {}, [
    el('input', { class: 'name', value: name }, []),
    bioAs === 'text'
      ? el('textarea', { class: 'bio' }, bioText === '' ? [] : [tx(bioText)])
      : el('textarea', { class: 'bio', value: bioText }, []),
    el('textarea', { class: 'notes' }, m.notes === '' ? [] : [tx(m.notes)]),
    el('select', { class: 'size' }, ['s', 'm', 'l'].map((v) => el('option', { value: v, ...(m.size === v ? { selected: '' } : {}) }, [tx(v)]))),
    level,
    radio('red'),
    radio('blue'),
    el('input', { class: 'agree', type: 'checkbox', ...(m.agree ? { checked: '' } : {}) }, []),
    el('span', { class: 'echo' }, [tx(echoOf(m))]),
  ]);
}

async function boot(root, model, hydrate = true) {
  const warns = [];
  const realWarn = console.warn;
  console.warn = (...a) => warns.push(a.join(' '));
  try {
    const app = await mount({ wasm: bytes, root, flags: JSON.stringify(model), dom: fakeDom, hydrate });
    return { app, warns };
  } finally {
    console.warn = realWarn;
  }
}

const staged = (model, opts) => {
  const r = new El('#root');
  fakeDom.append(r, ssrDom(model, opts));
  return r;
};

const model = { name: 'Ann', bio: 'Line one\nLine two', notes: 'n1', size: 'm', level: 'high', color: 'blue', agree: true };
const fresh = new El('#root');
await boot(fresh, model, false);

// --- A clean claim, the textarea's value written as its text ---

{
  const r = staged(model);
  const [name, bio, notes, size, level] = r.children[0].children;
  const notesText = notes.children[0];
  const { app, warns } = await boot(r, model);
  expect('forms claim cleanly', JSON.stringify(app.hydration()), '{"claimed":true,"mismatch":null}');
  expect('no warning', warns.length, 0);
  expect('every control was claimed', r.children[0].children.slice(0, 5).every((c, k) => c === [name, bio, notes, size, level][k]), true);
  expect('the textarea text that carried the value is gone', bio.children.length, 0);
  expect('and the textarea holds the value', bio.value, model.bio);
  expect('the value attribute the view declares is there', bio.attrs.get('value'), model.bio);
  expect('a textarea whose value is its text keeps the text node', notes.children[0] === notesText, true);
  expect('the select the markup could not set shows the declared value', level.value, 'high');
  expect('claimed page equals the client build', html(r), html(fresh));
}

// --- The older markup: the value as an attribute HTML ignores ---

{
  const r = staged(model, { bioAs: 'attr' });
  const bio = r.children[0].children[1];
  const { app } = await boot(r, model);
  expect('the attribute form claims cleanly too', app.hydration().mismatch, null);
  expect('and the textarea holds the value', bio.value, model.bio);
  expect('page equals the client build', html(r), html(fresh));
}

// --- A server whose textarea text disagrees ---

{
  const r = staged(model, { bioText: 'stale' });
  const bio = r.children[0].children[1];
  const { app } = await boot(r, model);
  expect('stale textarea text is reported', app.hydration().mismatch, 'expected the <textarea> to hold "Line one\\nLine two" but the server rendered "stale"');
  expect('and replaced by the value', bio.value, model.bio);
  expect('repaired page equals the client build', html(r), html(fresh));
}

// --- Everything changed before the app booted ---

{
  const before = { ...model, level: 'low', color: 'blue', agree: true };
  const r = staged(before);
  const [name, bio, notes, size, level, red, blue, agree, echo] = r.children[0].children;
  // What the user did while the wasm was still on its way.
  name.value = 'Annie';
  bio.value = 'edited bio';
  notes.value = 'edited notes';
  size.children[1].selected = false; size.children[2].selected = true; size.value = 'l';
  level.children[1].selected = true; level.children[0].selected = false; level.value = 'high';
  red.checked = true; blue.checked = false;
  agree.checked = false;
  const { app, warns } = await boot(r, before);
  expect('typing ahead is not a mismatch', app.hydration().mismatch, null);
  expect('and warns nothing', warns.length, 0);
  expect('the text input kept what was typed', name.value, 'Annie');
  expect('the value textarea kept what was typed', bio.value, 'edited bio');
  expect('the text textarea kept what was typed', notes.value, 'edited notes');
  expect('the select kept the pick', size.children.map((o) => (o.selected ? 'x' : '-')).join(''), '--x');
  expect('the value select kept the pick', level.value, 'high');
  expect('the radio kept the pick', `${red.checked} ${blue.checked}`, 'true false');
  expect('the checkbox kept the untick', agree.checked, false);
  expect('the app learned all of it', textOf(echo), 'Annie|edited bio|edited notes|l|high|red|no');
  // The model now agrees with the page, so a re-render keeps it.
  expect('the declared values follow the model', `${name.attrs.get('value')} ${bio.attrs.get('value')}`, 'Annie edited bio');
}

// --- A refused pre-boot value ---

{
  const r = staged(model);
  const [name, , , , , , , , echo] = r.children[0].children;
  name.value = 'Ann!';
  await boot(r, model);
  expect('the app refused it, so the field shows the model', name.value, 'Ann');
  expect('and the model is unchanged', echo.children.map((t) => t.text).join(''), echoOf(model));
}

// --- A stale server value the user typed over ---

{
  const r = staged(model, { name: 'Old' });
  const [name, , , , , , , , echo] = r.children[0].children;
  name.value = 'Mine';
  const { app } = await boot(r, model);
  expect('the stale value is reported', app.hydration().mismatch, 'expected value="Ann" on <input> but the server rendered value="Old"');
  expect('but what the user typed wins', name.value, 'Mine');
  expect('and reached the app', textOf(echo).startsWith('Mine|'), true);
}

// --- An untouched radio group and checkbox end up as the view says ---

{
  const r = staged({ ...model, color: 'red', agree: false });
  const [, , , , , red, blue, agree] = r.children[0].children;
  const { app } = await boot(r, model);
  expect('a group checked differently on the server is a mismatch', app.hydration().mismatch !== null, true);
  expect('the view picks the radio', `${red.checked} ${blue.checked}`, 'false true');
  expect('and ticks the checkbox', agree.checked, true);
}

// --- A delivery that re-renders a later control away ---

{
  // The name arrives first and hides the checkbox, so the checkbox's own
  // pre-boot change must not be delivered through the handler of a node the
  // app no longer renders.
  const r = staged(model);
  const [name, , , , , , , agree, echo] = r.children[0].children;
  name.value = 'hide';
  agree.checked = false;
  const { app } = await boot(r, model);
  expect('nothing crashed', app.hydration().mismatch, null);
  expect('the checkbox is gone from the page', r.children[0].children.includes(agree), false);
  expect('the app got the name and nothing for the checkbox', echo.children.map((t) => t.text).join(''), echoOf({ ...model, name: 'hide' }));
}
