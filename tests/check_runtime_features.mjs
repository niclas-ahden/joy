// Node harness for the runtime.js build.roc generates per app (see
// tools/runtime): it holds the feature code of exactly the platform
// functions the app's wasm calls. This rests on the compiler dropping the
// functions an app never calls together with their string literals, and on
// literals of 12 bytes or more sitting in the wasm's data as plain bytes. A
// compiler that changed either fails here, before an app ships a runtime.js
// without code it needs.
// Run from the repo root: node tests/check_runtime_features.mjs
import { readFileSync } from 'node:fs';
import { expect, runtimePath } from './harness.mjs';

const has = (js, id) => js.includes(`'${id}'`);
const media = ['stream', 'levels', 'record', 'finish', 'audio_summary', 'object_url', 'play', 'pause', 'seek'].map((op) => `joy/media/${op}`);

// The play-only app: Media.play and the helper it needs, nothing else.
const playOnly = readFileSync(runtimePath('media_play_only'), 'utf8');
expect('a play-only app gets play', has(playOnly, 'joy/media/play'), true);
expect('and the helper play needs', playOnly.includes('function mediaElement('), true);
expect('and none of the other media operations', media.filter((id) => id !== 'joy/media/play' && has(playOnly, id)).join(', '), '');
expect('nor helpers play does not need', playOnly.includes('const streams = new Map()'), false);

// The voice memo calls every media function.
const memo = readFileSync(runtimePath('voice_memo'), 'utf8');
expect('the voice memo gets every media operation it calls', media.filter((id) => !has(memo, id)).join(', '), '');

// An app that uses no feature gets the core alone.
const counter = readFileSync(runtimePath('counter'), 'utf8');
expect('an app without features gets none', counter.includes("defineOperation('joy/"), false);
expect('and says so', counter.includes('(see tools/runtime): none'), true);

// The page title, scrolling, document clicks and the clipboard ship with an
// app that calls them, and the DOM operations it does not call stay out.
const doc = readFileSync(runtimePath('document'), 'utf8');
const docOps = ['joy/dom/set_title', 'joy/dom/scroll_to', 'joy/dom/document_clicks', 'joy/clipboard/write_text', 'joy/clipboard/write_text_of'];
expect('the document app gets its title, scroll, click and clipboard operations', docOps.filter((id) => !has(doc, id)).join(', '), '');
expect('and not focus, which it never calls', has(doc, 'joy/dom/focus'), false);
