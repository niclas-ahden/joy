// The guide's editors. Each [data-editor] block (see Doc.editor)
// becomes an editor beside the running app. The Roc compiler, built for the
// browser, runs in one worker that every editor on the page shares, and
// Joy's own runtime mounts what it builds, the way a page mounts a bundle. An
// edit hot reloads the app, so it keeps its state, and a report from roc
// covers the app until the code compiles again.
//
// Nothing loads until an editor comes into view: the compiler is a large
// download, and most visits never reach one.
const BASE = new URL('./editor/', import.meta.url);
const CODEMIRROR = 'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16';

const blocks = [...document.querySelectorAll('[data-editor]')];
const seen = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    seen.unobserve(entry.target);
    start(entry.target);
  }
}, { rootMargin: '200px' });
for (const block of blocks) seen.observe(block);

// --- What every editor shares ---

let compiler = null;
let nextId = 0;
const waiting = new Map();
function ask(message) {
  compiler ??= (() => {
    const worker = new Worker(new URL('compiler-worker.js', BASE));
    worker.onmessage = (event) => {
      const done = waiting.get(event.data.id);
      waiting.delete(event.data.id);
      done?.(event.data);
    };
    return worker;
  })();
  const id = ++nextId;
  return new Promise((resolve) => {
    waiting.set(id, resolve);
    compiler.postMessage({ id, ...message });
  });
}
const compile = (source) => ask({ source, hot: true });
// The source the way `roc format` leaves it.
const format = (source) => ask({ format: source });

let runtime = null;
const loadRuntime = () => (runtime ??= import(new URL('runtime-hot.js', BASE).href));

let editorLib = null;
function loadEditor() {
  editorLib ??= new Promise((resolve) => {
    const css = document.createElement('link');
    css.rel = 'stylesheet';
    css.href = `${CODEMIRROR}/codemirror.min.css`;
    const hints = document.createElement('link');
    hints.rel = 'stylesheet';
    hints.href = `${CODEMIRROR}/addon/hint/show-hint.min.css`;
    document.head.append(css, hints);
    const script = (src) => new Promise((done, fail) => {
      const tag = document.createElement('script');
      tag.src = src;
      tag.onload = done;
      tag.onerror = fail;
      document.head.append(tag);
    });
    // A plain text area stands in when the editor cannot load. Without
    // show-hint the editor works and suggests nothing.
    script(`${CODEMIRROR}/codemirror.min.js`)
      .then(() => script(`${CODEMIRROR}/mode/elm/elm.min.js`))
      .then(() => script(`${CODEMIRROR}/addon/hint/show-hint.min.js`).catch(() => {}))
      .then(() => resolve(globalThis.CodeMirror), () => resolve(null));
  });
  return editorLib;
}

// The compiler sees the app as /app/main.roc beside the platform it was
// built with, so a sample's release URL for the platform points there.
const forCompiler = (source) => source.replace(/pf:\s*platform\s*"[^"]*"/, 'pf: platform "../platform/main.roc"');

// roc colours its reports for a terminal. The escapes become spans that end
// with their line. Prose wraps to the pane. A line of carets and the code above
// it never wrap, as the carets point by column.
const COLOURS = { 31: '#ff6b6b', 32: '#7bd88f', 33: '#ffd866', 34: '#78a9ff', 35: '#d38cff', 36: '#5ad4e6', 90: '#8b8b96', 91: '#ff8787', 92: '#9be9a8', 93: '#ffe08a', 94: '#a0c4ff', 95: '#e0aaff', 96: '#89ddff' };
function ansiToHtml(text) {
  const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const lines = [];
  let line = '';
  let open = [];
  for (const part of text.split(/(\x1b\[[0-9;]*m|\n)/)) {
    if (part === '\n') {
      lines.push(line + '</span>'.repeat(open.length));
      line = open.join('');
      continue;
    }
    const match = part.match(/^\x1b\[([0-9;]*)m$/);
    if (!match) { line += escape(part); continue; }
    for (const code of match[1].split(';').map(Number)) {
      let tag = '';
      if (code === 0) { line += '</span>'.repeat(open.length); open = []; }
      else if (code === 1) tag = '<span style="font-weight:bold">';
      else if (COLOURS[code]) tag = `<span style="color:${COLOURS[code]}">`;
      if (tag) { line += tag; open.push(tag); }
    }
  }
  lines.push(line + '</span>'.repeat(open.length));
  const carets = lines.map((html) => /^\s*\^+\s*$/.test(html.replace(/<[^>]*>/g, '')));
  return lines
    .map((html, i) => (carets[i] || carets[i + 1] ? `<span class="ed-quote">${html}</span>` : html))
    .join('\n');
}

// Where the problems of a report are in `source`, the code it is about, as
// stretches of one line each. roc heads a problem with its file, line and
// column. One on a single line it underlines with carets below the line it
// quotes. One that spans lines it quotes whole, with no carets, so that one
// runs for as long as the report goes on quoting the code. A problem in
// another file has no place in the editor.
//
// Many lines underlined say little about where to look. A hint of roc's may
// name what to change, and roc colours the names its first sentence is about,
// like a tag that is not in the union. Where such a name is in the stretch,
// it is what is underlined, the hint's before the sentence's.
function problems(report, source) {
  const colour = /\x1b\[[0-9;]*m/g;
  const code = source.split('\n');
  const found = [];
  for (const raw of report.split(/^(?:\x1b\[[0-9;]*m)*── /m).slice(1)) {
    const part = raw.replace(colour, '');
    const head = /^\S+ (.+?) ─+ \/app\/main\.roc:(\d+):(\d+)\n/.exec(part);
    if (!head) continue;
    const line = Number(head[2]) - 1;
    const ch = Number(head[3]) - 1;
    const said = part.slice(head[0].length).split('\n');
    const title = `${head[1]}: ${said.find((l) => l.trim() !== '') ?? ''}`;
    const carets = /^ *(\^+) *$/m.exec(part);
    if (carets || code[line] === undefined) {
      found.push({ line, from: ch, to: ch + (carets ? carets[1].length : 1), title });
      continue;
    }
    // WORKAROUND: roc-lang/roc#13070. A match with a pattern its value cannot
    // be is reported at the line of `match` and the column of the pattern,
    // which is no place in particular. So the quoted line is also looked for
    // as a whole. When the position is right, compare from the column on
    // only, and `first` is `ch`.
    const indent = (at) => code[at].length - code[at].trimStart().length;
    const quoted = said.findIndex((l) => l.trim() !== '' && (l.trim() === code[line].slice(ch).trim() || l.trim() === code[line].trim()));
    if (quoted < 0) {
      found.push({ line, from: ch, to: ch + 1, title });
      continue;
    }
    const first = said[quoted].trim() === code[line].slice(ch).trim() ? ch : indent(line);
    let last = line;
    for (let k = 1; said[quoted + k] !== undefined && code[line + k] !== undefined && said[quoted + k].trim() === code[line + k].trim(); k++) {
      if (code[line + k].trim() !== '') last = line + k;
    }
    const sentence = raw.split('\n').slice(1).join('\n').trim().split(/\n\s*\n/)[0];
    const coloured = [...sentence.matchAll(/\x1b\[[0-9;]*m([A-Za-z_]\w*!?)\x1b\[/g)].map((m) => m[1]);
    // WORKAROUND: roc-lang/roc#13070. With that position the report points at
    // the whole match, and only its hint names the pattern to change. When
    // the report points at the pattern, drop `hinted` and `hint`.
    const hinted = [...part.matchAll(/[Mm]aybe ([A-Za-z_]\w*!?) should be /g)].map((m) => m[1]);
    const whole = [];
    for (let at = line; at <= last; at++) {
      if (code[at].trim() !== '') whole.push({ line: at, from: at === line ? first : indent(at), to: code[at].length, title });
    }
    const where = (names) => whole.flatMap((stretch) => names.flatMap((name) =>
      [...code[stretch.line].matchAll(new RegExp(`(?<![\\w.])${name.replace('!', '\\!')}(?![\\w!])`, 'g'))]
        .filter((m) => m.index >= stretch.from)
        .map((m) => ({ line: stretch.line, from: m.index, to: m.index + name.length, title }))));
    const hint = where(hinted);
    const named = hint.length ? [] : where(coloured);
    found.push(...(hint.length ? hint : named.length ? named : whole));
  }
  return found;
}

function encode(text) {
  let s = '';
  for (const byte of new TextEncoder().encode(text)) s += String.fromCharCode(byte);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

const el = (tag, cls, ...children) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  node.append(...children);
  return node;
};

// The line between the code and the app moves with the pointer or the arrow
// keys. Each side keeps at least a fifth of the width.
const EVEN = 55;
function resizable(split, body, ui, editor) {
  let percent = EVEN;
  // Where on the line the pointer took hold, so it does not jump.
  let grab = 0;
  const set = (value) => {
    percent = Math.min(80, Math.max(20, value));
    body.style.setProperty('--ed-split', `${percent}%`);
    split.setAttribute('aria-valuenow', String(Math.round(percent)));
  };
  split.tabIndex = 0;
  split.setAttribute('role', 'separator');
  split.setAttribute('aria-orientation', 'vertical');
  split.setAttribute('aria-label', 'Resize the code and the app');
  split.setAttribute('aria-valuemin', '20');
  split.setAttribute('aria-valuemax', '80');
  set(EVEN);

  split.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    split.setPointerCapture(event.pointerId);
    grab = event.clientX - split.getBoundingClientRect().left;
    split.classList.add('dragging');
    ui.classList.add('resizing');
  });
  split.addEventListener('pointermove', (event) => {
    if (!split.hasPointerCapture(event.pointerId)) return;
    const box = body.getBoundingClientRect();
    set(((event.clientX - grab - box.left) / box.width) * 100);
  });
  const stop = (event) => {
    if (!split.hasPointerCapture(event.pointerId)) return;
    split.releasePointerCapture(event.pointerId);
    split.classList.remove('dragging');
    ui.classList.remove('resizing');
    editor.refresh();
  };
  split.addEventListener('pointerup', stop);
  split.addEventListener('pointercancel', stop);
  split.addEventListener('dblclick', () => { set(EVEN); editor.refresh(); });
  split.addEventListener('keydown', (event) => {
    const step = event.shiftKey ? 10 : 2;
    if (event.key === 'ArrowLeft') set(percent - step);
    else if (event.key === 'ArrowRight') set(percent + step);
    else if (event.key === 'Home') set(20);
    else if (event.key === 'End') set(80);
    else return;
    event.preventDefault();
    editor.refresh();
  });
}

// --- What an editor suggests ---
//
// The names an editor offers while you type are read from the code the
// compiler compiles: the modules of joy-html and of the platform, which the
// manifest of the compiler's files lists. A module's names are the annotated
// ones of its type, each with its type and the comment above it.
//
// This is not a language server. It knows which modules the code imports and
// what each of their names returns, and nothing about the types in the code.
let library = null;
function loadLibrary() {
  library ??= (async () => {
    const manifest = await (await fetch(new URL('fs/manifest.json', BASE))).json();
    const files = [...manifest.common, ...manifest.hot].filter(([path]) => /\/[A-Z]\w*\.roc$/.test(path));
    return Promise.all(files.map(async ([path, url]) => ({
      path,
      name: path.split('/').pop().replace('.roc', ''),
      names: declared(await (await fetch(new URL(url, BASE))).text()),
    })));
  })().catch(() => []);
  return library;
}

function declared(source) {
  const found = new Map();
  const lines = source.split('\n');
  // A module's names are in the block of its type, from the line that ends
  // in `.{` to the `}` that closes it. What comes after is its own.
  let inside = false;
  lines.forEach((line, at) => {
    if (!inside && /^\S.*\.\{$/.test(line)) inside = true;
    else if (inside && line === '}') inside = false;
    const head = inside && /^\t([a-z_]\w*!?) : (.+)$/.exec(line);
    if (!head || found.has(head[1])) return;
    const doc = [];
    for (let up = at - 1; up >= 0 && lines[up].startsWith('\t##'); up--) doc.unshift(lines[up].slice(3).trim());
    found.set(head[1], { name: head[1], type: head[2], doc: doc.join(' ') });
  });
  return [...found.values()];
}

// The imports of `source` that are of a module the compiler has. The app's
// header says which package or platform a shorthand like `html` stands for.
function importsOf(source, modules) {
  const origin = new Map();
  for (const m of source.matchAll(/^\s*(\w+):\s*(platform\s+)?"([^"]*)"/gm)) {
    origin.set(m[1], m[2] ? '/platform/' : `/${m[3].split('/').pop().split('.')[0]}/`);
  }
  const found = [];
  source.split('\n').forEach((text, line) => {
    const m = /^import (\w+)\.(\w+)(?: as (\w+))?(?: exposing \[([^\]]*)\])?/.exec(text);
    const module = m && modules.find((one) => one.name === m[2] && one.path.includes(origin.get(m[1]) ?? '\0'));
    if (!module) return;
    const exposing = m[4] === undefined ? null : m[4].split(',').map((s) => s.trim()).filter(Boolean);
    found.push({ module, alias: m[3] ?? m[2], exposing, line });
  });
  return found;
}

// Which of an element's two lists the cursor is in: "Attribute" in the first,
// "Html" in the second, null anywhere else. An element is a call with two
// lists, so the first comes after `(` and the second after a comma.
function listAt(cm, cursor) {
  const text = cm.getRange({ line: Math.max(0, cursor.line - 60), ch: 0 }, cursor);
  let closed = 0;
  for (let i = text.length - 1; i >= 0; i--) {
    if (')]}'.includes(text[i])) closed++;
    else if ('([{'.includes(text[i])) {
      if (closed > 0) { closed--; continue; }
      if (text[i] !== '[') return null;
      const before = text.slice(0, i).trimEnd().slice(-1);
      return before === '(' ? 'Attribute' : before === ',' ? 'Html' : null;
    }
  }
  return null;
}

// What a name gives: the type its annotation ends in, like Html or Attribute.
const gives = (type) => /^([A-Z]\w*)/.exec(type.split('->').pop().trim())?.[1] ?? '';

// The suggestions at the cursor, as CodeMirror's show-hint wants them, or
// null for none. After `Module.` they are that module's names. A bare name
// is looked for in the modules imported with `exposing`, and picking one
// the import does not list yet adds it there.
function suggestionsAt(cm, modules) {
  const cursor = cm.getCursor();
  const before = cm.getLine(cursor.line).slice(0, cursor.ch);
  // Not in a string or a comment.
  const code = before.replace(/"(?:[^"\\]|\\.)*"/g, '""');
  if (code.includes('#') || code.split('"').length % 2 === 0) return null;
  const imports = importsOf(cm.getValue(), modules);
  const qualified = /\b([A-Z]\w*)\.([a-z_]\w*!?)?$/.exec(before);
  const bare = qualified ? null : /(?<![\w.])[a-z_]\w*$/.exec(before);
  if (!qualified && !bare) return null;
  const typed = qualified ? qualified[2] ?? '' : bare[0];
  let found = [];
  if (qualified) {
    const from = imports.find((one) => one.alias === qualified[1]);
    found = (from?.module.names ?? []).map((name) => ({ ...name, from: null }));
  } else {
    const all = imports.filter((one) => one.exposing).flatMap((from) => from.module.names.map((name) => ({ ...name, from })));
    const list = listAt(cm, cursor);
    const fitting = all.filter((name) => gives(name.type) === list);
    found = fitting.length ? fitting : all;
  }
  found = found.filter((name) => name.name.startsWith(typed) && name.name !== typed).sort((a, b) => a.name.localeCompare(b.name));
  if (!found.length) return null;
  return {
    from: { line: cursor.line, ch: cursor.ch - typed.length },
    to: cursor,
    list: found.map((name) => ({
      text: name.name,
      render: (item) => {
        item.append(el('span', 'ed-hint-name', name.name), el('span', 'ed-hint-type', name.type));
        if (name.doc) item.title = name.doc;
      },
      hint: (editor, data) => editor.operation(() => {
        editor.replaceRange(name.name, data.from, data.to, 'complete');
        if (!name.from || name.from.exposing.includes(name.name)) return;
        const line = editor.getLine(name.from.line);
        const at = { line: name.from.line, ch: line.lastIndexOf(']') };
        editor.replaceRange((name.from.exposing.length ? ', ' : '') + name.name, at, at, 'complete');
      }),
    })),
  };
}

// Suggests in `cm`: on Ctrl+Space anywhere, and while typing after
// `Module.` or in one of an element's lists, where a name is most likely
// one of the package's.
function suggestIn(cm, modules) {
  if (!cm.showHint || !modules.length) return;
  const options = { hint: (editor) => suggestionsAt(editor, modules), completeSingle: false };
  cm.setOption('extraKeys', { 'Ctrl-Space': () => cm.showHint(options) });
  cm.on('inputRead', (editor, change) => {
    if (change.origin !== '+input' || !/[\w.]$/.test(change.text[0])) return;
    const cursor = editor.getCursor();
    const before = editor.getLine(cursor.line).slice(0, cursor.ch);
    if (/\b[A-Z]\w*\.\w*$/.test(before) || listAt(editor, cursor)) editor.showHint(options);
  });
}

// --- One editor ---

async function start(block) {
  const original = block.querySelector('code').textContent;
  const file = block.querySelector('.file')?.textContent ?? 'main.roc';

  const status = el('span', 'ed-status', 'Loading the compiler...');
  const formatButton = el('button', 'ed-button', 'Format');
  formatButton.type = 'button';
  formatButton.title = 'Format the code as roc format does (Shift+Alt+F)';
  const reset = el('button', 'ed-button', 'Reset');
  reset.type = 'button';
  const open = el('a', 'ed-open', 'Open full screen');
  open.target = '_blank';
  const editorPane = el('div', 'ed-code');
  const appPane = el('div', 'ed-app');
  const report = el('pre', 'ed-report');
  report.setAttribute('aria-live', 'polite');
  const output = el('div', 'ed-output', appPane, report);
  const split = el('div', 'ed-split');
  const body = el('div', 'ed-body', editorPane, split, output);
  const ui = el('div', 'ed',
    el('div', 'code-head ed-head', el('span', 'file', file), status, formatButton, reset, open),
    body);

  // The static block stays until the editor can take its place.
  const [CodeMirror] = await Promise.all([loadEditor(), loadRuntime()]);
  block.replaceChildren(ui);

  let editor;
  if (CodeMirror) {
    const cm = CodeMirror(editorPane, { value: original, mode: 'elm', lineNumbers: true, indentUnit: 4, tabSize: 4, viewportMargin: Infinity });
    // A folded editor (see Doc.editor_folded) shows the app's header
    // as one button, which opens it, as does moving the cursor into it. The
    // code is whole all along, so the line numbers are those of a report.
    let header = null;
    const fold = () => {
      header = null;
      if (block.dataset.editor !== 'folded' || !cm.getLine(0).startsWith('app ')) return;
      const end = cm.getValue().split('\n').indexOf('}');
      if (end < 1) return;
      const chip = el('button', 'ed-fold', 'app header');
      chip.type = 'button';
      chip.title = 'Show the header: the platform and the packages the app uses';
      header = cm.markText({ line: 0, ch: 0 }, { line: end, ch: 1 }, { replacedWith: chip, inclusiveLeft: true, clearOnEnter: true });
      chip.addEventListener('click', () => { header.clear(); cm.focus(); });
    };
    fold();
    loadLibrary().then((modules) => suggestIn(cm, modules));
    // The compiler's problems, underlined where they are. Hovering one says what it is.
    let marked = [];
    const mark = (found) => {
      for (const one of marked) one.clear();
      marked = found.map((p) => cm.markText({ line: p.line, ch: p.from }, { line: p.line, ch: p.to }, { className: 'ed-squiggle', title: p.title }));
    };
    editor = { get: () => cm.getValue(), set: (v) => { cm.setValue(v); fold(); }, onChange: (f) => cm.on('change', f), refresh: () => cm.refresh(), mark,
      // Keeps the cursor and the scroll, and Ctrl+Z takes it back. A header
      // that was folded stays folded.
      replace: (v) => { const at = cm.getCursor(); const { left, top } = cm.getScrollInfo(); const folded = Boolean(header?.find()); cm.setValue(v); if (folded) fold(); cm.setCursor(at); cm.scrollTo(left, top); } };
  } else {
    const area = el('textarea', 'ed-textarea');
    area.value = original;
    area.spellcheck = false;
    area.setAttribute('aria-label', 'Roc source');
    editorPane.append(area);
    editor = { get: () => area.value, set: (v) => { area.value = v; }, onChange: (f) => area.addEventListener('input', f), refresh: () => {}, mark: () => {},
      replace: (v) => { const at = area.selectionStart; area.value = v; area.selectionStart = area.selectionEnd = at; area.dispatchEvent(new Event('input')); } };
  }

  resizable(split, body, ui, editor);

  const { mount } = await loadRuntime();
  let app = null;
  let busy = false;
  let again = false;

  async function fresh(wasm) {
    app?.unmount();
    const root = document.createElement('div');
    appPane.replaceChildren(root);
    return mount({ wasm, root, flags: '' });
  }

  async function run() {
    if (busy) { again = true; return; }
    busy = true;
    status.textContent = 'Compiling...';
    const source = forCompiler(editor.get());
    open.href = `${new URL('index.html', BASE).href}#code=${encode(source)}`;
    const result = await compile(source);
    if (result.ok) {
      editor.mark([]);
      try {
        if (app?.reload) {
          try {
            await app.reload(result.wasm, { replay: 'skip' });
          } catch (err) {
            console.warn('Joy guide: the hot reload failed, so the app starts over', err);
            app = await fresh(result.wasm);
          }
        } else {
          app = await fresh(result.wasm);
        }
        report.classList.remove('shown');
        report.textContent = '';
        status.textContent = `Compiled in ${result.ms.toFixed(0)} ms`;
      } catch (err) {
        report.textContent = `The app crashed while starting.\n\n${err?.stack ?? err}`;
        report.classList.add('shown');
        status.textContent = 'The app crashed';
      }
    } else {
      editor.mark(problems(result.report || '', source));
      report.innerHTML = ansiToHtml(result.report || `The compiler stopped (code ${result.rc}) without a report.`);
      report.classList.add('shown');
      status.textContent = result.rc === 1 ? 'Does not compile' : 'The compiler failed';
    }
    busy = false;
    if (again) { again = false; run(); }
  }

  let timer = null;
  const soon = () => { clearTimeout(timer); timer = setTimeout(run, 400); };
  editor.onChange(soon);
  ui.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) { event.preventDefault(); clearTimeout(timer); run(); }
  });
  // The formatted code takes the place of what was typed only if nothing was
  // typed meanwhile, and it compiles like any edit.
  async function tidy() {
    const before = editor.get();
    const result = await format(before);
    if (result.ok) {
      if (result.formatted !== before && editor.get() === before) editor.replace(result.formatted);
      return;
    }
    status.textContent = 'Cannot format code that does not parse';
  }
  formatButton.addEventListener('click', tidy);
  ui.addEventListener('keydown', (event) => {
    if (event.code === 'KeyF' && event.shiftKey && event.altKey) { event.preventDefault(); tidy(); }
  });
  reset.addEventListener('click', () => {
    app?.unmount();
    app = null;
    editor.set(original);
    clearTimeout(timer);
    run();
  });

  run();
}
