// Node harness for the Media module, on the voice_memo example with fake
// browser media: the microphone stays open exactly while Media.stream is in
// the app's subscriptions (its tracks stop once the recording is finished,
// with no cleanup code in the app), a recording comes back as an ordinary
// file, a refused microphone and a page that is not secure arrive as typed
// problems, and playback reaches the <audio> element by its selector. It
// runs the example's own generated runtime.js, so it covers the media
// operations as an app ships them. The real browser APIs are covered by
// tests/e2e/voice_memo_test.roc.
// Run from the repo root: node tests/check_media.mjs
import { readFileSync } from 'node:fs';
import { El, byId, fakeDom, find, htmlBare } from './fakedom.mjs';
import { expect, runtimePath, wasmPath } from './harness.mjs';

const { mount } = await import(`../${runtimePath('voice_memo')}`);

const bytes = readFileSync(wasmPath('voice_memo'));
const tick = () => new Promise((r) => setTimeout(r, 0));
const settled = async (pred) => {
  for (let i = 0; i < 500 && !pred(); i++) await tick();
  return pred();
};

// --- Fake media ---------------------------------------------------------------

let answer = null; // what getUserMedia does next: a stream, or an error to throw
const opened = [];
class FakeTrack {
  constructor() { this.stopped = false; }
  stop() { this.stopped = true; }
}
class FakeStream {
  constructor() { this.tracks = [new FakeTrack()]; }
  getTracks() { return this.tracks; }
}
const devices = {
  getUserMedia: async (constraints) => {
    if (answer instanceof Error) throw answer;
    const stream = new FakeStream();
    opened.push({ constraints, stream });
    return stream;
  },
};
Object.defineProperty(globalThis.navigator, 'mediaDevices', { value: devices, configurable: true });

class FakeRecorder {
  static isTypeSupported(type) { return type === 'audio/webm'; }
  constructor(stream, options) {
    this.stream = stream;
    this.mimeType = options.mimeType ?? '';
    this.audioBitsPerSecond = options.audioBitsPerSecond ?? 64000;
    this.state = 'inactive';
    FakeRecorder.made.push(this);
  }
  start() { this.state = 'recording'; }
  stop() {
    this.state = 'inactive';
    this.ondataavailable?.({ data: { size: 4, bytes: 'take' } });
    queueMicrotask(() => this.onstop?.());
  }
}
FakeRecorder.made = [];
globalThis.MediaRecorder = FakeRecorder;

globalThis.File = class {
  constructor(parts, name, options) {
    this.name = name;
    this.type = options?.type ?? '';
    this.size = parts.reduce((n, p) => n + p.size, 0);
  }
  async arrayBuffer() { return new ArrayBuffer(8); }
};

// Two seconds of audio rising from silence to full scale.
globalThis.AudioContext = class {
  createMediaStreamSource() { return { connect() {}, disconnect() {} }; }
  createAnalyser() { return { fftSize: 0, getByteTimeDomainData: (a) => a.fill(192) }; }
  async decodeAudioData() {
    const samples = new Float32Array(2000).map((_, i) => i / 2000);
    return { duration: 2, getChannelData: () => samples };
  }
  close() {}
};
globalThis.requestAnimationFrame = (fn) => setTimeout(fn, 1);
globalThis.cancelAnimationFrame = (handle) => clearTimeout(handle);
URL.createObjectURL = (file) => `blob:fake/${file.name}`;

// --- The memo -------------------------------------------------------------------

const root = new El('#root');
await mount({ wasm: bytes, root, flags: '', dom: fakeDom });
const html = () => htmlBare(root);

expect('nothing is opened before Record', opened.length, 0);
find(root, 'Record').listeners.click();
expect('Record asks for the microphone', await settled(() => html().includes('recording')), true);
expect('only audio is asked for', JSON.stringify(opened[0]?.constraints), '{"audio":true,"video":false}');
expect('a recorder runs on the opened stream', FakeRecorder.made[0]?.stream === opened[0].stream, true);
expect('a browser recording below the floor is raised to it', FakeRecorder.made.at(-1).audioBitsPerSecond, 128000);
expect('levels arrive in thousandths', await settled(() => html().includes('level 500')), true);

find(root, 'Stop').listeners.click();
expect('the take comes back as a file', await settled(() => html().includes('memo.webm, 4 bytes')), true);
expect('the microphone is let go once nothing subscribes to it', opened[0].stream.tracks[0].stopped, true);
expect('the summary has its length and peaks', await settled(() => html().includes('2000 ms, 20 peaks')), true);
const bars = [...byId(root, 'waveform').children[0].text];
const levels = bars.map((b) => '▁▂▃▄▅▆▇█'.indexOf(b));
expect('the waveform has a bar per peak', bars.length, 20);
expect('the waveform rises with the audio', levels.every((l, i) => i === 0 || l >= levels[i - 1]) && levels[0] === 0 && levels[19] >= 6, true);
expect('the audio element plays the file', byId(root, 'memo').attrs.get('src'), 'blob:fake/memo.webm');

const audio = byId(root, 'memo');
let played = 0;
audio.play = async () => { played++; };
audio.pause = () => {};
audio.currentTime = 5;
find(root, 'Play').listeners.click();
expect('Media.play reaches the element by its selector', await settled(() => played === 1), true);
find(root, 'Rewind').listeners.click();
expect('Media.seek moves it', await settled(() => audio.currentTime === 0), true);

// --- Refusals ---------------------------------------------------------------------

const denied = new Error('Permission denied');
denied.name = 'NotAllowedError';
answer = denied;
find(root, 'Record').listeners.click();
expect('a refused microphone arrives as NotAllowed', await settled(() => html().includes('failed: microphone not allowed')), true);

// A page that is not secure has no mediaDevices at all.
Object.defineProperty(globalThis.navigator, 'mediaDevices', { value: undefined, configurable: true });
globalThis.isSecureContext = false;
find(root, 'Record').listeners.click();
expect('an insecure page arrives as Insecure', await settled(() => html().includes('failed: needs a secure page')), true);
