// The media feature: what the platform's Media module asks the browser for.
// Capture (getUserMedia), loudness (an AnalyserNode), recording
// (MediaRecorder), decoding an audio file (decodeAudioData), object URLs and
// <audio>/<video> playback. The app owns all state and draws everything,
// these operations only report numbers and hand over files.
//
// Streams and recorders live here under ids the app holds in its model. A
// stream lives exactly as long as the app's Media.stream subscription, and
// closing it stops its tracks and discards its unfinished recordings.
//
// A failure is thrown with the browser's error name (NotAllowedError,
// NotFoundError, ...), which the platform turns into Media.Problem.
//
// Each `////` line starts a section: an operation (`op`), an event source
// (`events`) or a `helper`, with the helpers it needs. An app's runtime.js
// holds the sections of the operations its wasm uses and the helpers those
// need (see tools/runtime), so this file is never served whole.

//// helper named
// An error with a name the platform tells failures apart by.
function named(name, message) {
  const err = new Error(message);
  err.name = name;
  return err;
}

//// helper thousandths
function thousandths(v) {
  return Math.min(1000, Math.round(v * 1000));
}

//// helper audio_context needs named
function audioContext() {
  const AudioContext = globalThis.AudioContext ?? globalThis.webkitAudioContext;
  if (!AudioContext) throw named('NotSupportedError', 'this browser has no Web Audio');
  return new AudioContext();
}

//// helper streams
const streams = new Map(); // id -> { stream, recorders: Set(recorder id) }
let nextStreamId = 1;
const recorders = new Map(); // id -> { recorder, chunks, streamId }
let nextRecorderId = 1;

function stopTracks(stream) {
  for (const track of stream.getTracks()) track.stop();
}

function discardRecording(id) {
  const entry = recorders.get(id);
  if (!entry) return;
  recorders.delete(id);
  entry.recorder.ondataavailable = null;
  entry.recorder.onstop = null;
  if (entry.recorder.state !== 'inactive') entry.recorder.stop();
}

// Stop the tracks and discard the recordings that were not finished.
function closeStream(id) {
  const entry = streams.get(id);
  if (!entry) return;
  for (const recorderId of entry.recorders) discardRecording(recorderId);
  stopTracks(entry.stream);
  streams.delete(id);
}

//// events joy/media/stream needs streams
// Ask for the devices, and report the stream's id once the user allows it,
// or the error's name. Closing before the answer lets the stream go at once.
defineEvents('joy/media/stream', (args, host, emit) => {
  const audio = args.bool();
  const video = args.bool();
  let closed = false;
  let id = 0;
  const devices = globalThis.navigator?.mediaDevices;
  if (!devices?.getUserMedia) {
    // Browsers leave mediaDevices out on pages that are not secure.
    const name = globalThis.isSecureContext === false ? 'SecurityError' : 'NotSupportedError';
    queueMicrotask(() => { if (!closed) emit(new WireWriter().u8(1).str(name)); });
    return () => { closed = true; };
  }
  devices.getUserMedia({ audio, video }).then(
    (stream) => {
      if (closed) return stopTracks(stream);
      id = nextStreamId++;
      streams.set(id, { stream, recorders: new Set() });
      emit(new WireWriter().u8(0).u32(id));
    },
    (err) => { if (!closed) emit(new WireWriter().u8(1).str(err?.name || 'Error')); },
  );
  return () => {
    closed = true;
    if (id !== 0) closeStream(id);
  };
});

//// events joy/media/levels needs streams thousandths
// The loudest sample since the last report, in thousandths of full scale,
// every `interval_ms`. A frame loop keeps the loudest, so short peaks
// between reports are not lost. Nothing is reported for a closed stream or
// in a browser without Web Audio.
defineEvents('joy/media/levels', (args, host, emit) => {
  const stream_id = args.u32();
  const interval_ms = args.u32();
  const entry = streams.get(stream_id);
  const AudioContext = globalThis.AudioContext ?? globalThis.webkitAudioContext;
  if (!entry || !AudioContext) return () => {};
  const ctx = new AudioContext();
  const source = ctx.createMediaStreamSource(entry.stream);
  const analyser = ctx.createAnalyser();
  analyser.fftSize = 2048;
  source.connect(analyser);
  const samples = new Uint8Array(analyser.fftSize);
  let peak = 0;
  let frame = 0;
  const accumulate = () => {
    frame = requestAnimationFrame(accumulate);
    analyser.getByteTimeDomainData(samples);
    for (let i = 0; i < samples.length; i++) {
      const v = Math.abs(samples[i] - 128) / 128;
      if (v > peak) peak = v;
    }
  };
  accumulate();
  const timer = setInterval(() => {
    emit(new WireWriter().u16(thousandths(peak)));
    peak = 0;
  }, interval_ms);
  return () => {
    clearInterval(timer);
    cancelAnimationFrame(frame);
    source.disconnect();
    ctx.close();
  };
});

//// op joy/media/record needs streams named
// Start a MediaRecorder on an open stream. With no container asked for,
// prefer Opus in webm and leave the rest to the browser (Safari records
// mp4). A browser that would record below the floor is raised to it.
defineOperation('joy/media/record', (args) => {
  const stream_id = args.u32();
  const mime_type = args.str();
  const min_audio_bits_per_second = args.u32();
  const entry = streams.get(stream_id);
  if (!entry) throw named('InvalidStateError', 'the stream is closed');
  if (!globalThis.MediaRecorder) throw named('NotSupportedError', 'this browser cannot record');
  const options = {};
  if (mime_type !== '') {
    if (!MediaRecorder.isTypeSupported(mime_type)) throw named('NotSupportedError', `cannot record ${mime_type}`);
    options.mimeType = mime_type;
  } else if (MediaRecorder.isTypeSupported('audio/webm')) {
    options.mimeType = 'audio/webm';
  }
  let recorder = new MediaRecorder(entry.stream, options);
  if ((recorder.audioBitsPerSecond || 0) < min_audio_bits_per_second) {
    recorder = new MediaRecorder(entry.stream, { ...options, audioBitsPerSecond: min_audio_bits_per_second });
  }
  const chunks = [];
  recorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
  recorder.start();
  const id = nextRecorderId++;
  recorders.set(id, { recorder, chunks, streamId: stream_id });
  entry.recorders.add(id);
  return new WireWriter().u32(id);
});

//// op joy/media/finish needs streams named
// Stop a recording and hand it to the app as a file, its extension
// following the container the browser recorded in.
defineOperation('joy/media/finish', (args, host) => {
  const recorder_id = args.u32();
  const name = args.str();
  const entry = recorders.get(recorder_id);
  if (!entry) throw named('InvalidStateError', 'no such recording');
  recorders.delete(recorder_id);
  streams.get(entry.streamId)?.recorders.delete(recorder_id);
  return new Promise((resolve, reject) => {
    entry.recorder.onerror = (e) => reject(e.error ?? named('UnknownError', 'recording failed'));
    entry.recorder.onstop = () => {
      const mime = entry.recorder.mimeType || '';
      const [extension, type] =
        mime.includes('mp4') ? ['m4a', 'audio/mp4']
        : mime.includes('ogg') ? ['ogg', 'audio/ogg']
        : ['webm', 'audio/webm'];
      const file = new File(entry.chunks, `${name}.${extension}`, { type });
      const added = host.addFile(file);
      resolve(new WireWriter().u32(added.id).str(added.name).str(added.mime).u64(added.size));
    };
    entry.recorder.stop();
  });
});

//// op joy/media/audio_summary needs named thousandths audio_context
// An audio file's length and `peak_count` peaks in thousandths, evenly
// spread over it. A recorder's file often has no duration in its metadata
// (Chrome reports Infinity), so the decoded audio is the source of truth.
defineOperation('joy/media/audio_summary', async (args, host) => {
  const file_id = args.u32();
  const peak_count = args.u32();
  const file = host.file(file_id);
  if (!file) throw named('NotFoundError', 'no such file');
  const ctx = audioContext();
  let decoded;
  try {
    decoded = await ctx.decodeAudioData(await file.arrayBuffer());
  } catch (err) {
    throw named('EncodingError', err?.message ?? 'the audio could not be decoded');
  } finally {
    ctx.close();
  }
  const samples = decoded.getChannelData(0);
  const peaks = [];
  if (peak_count > 0 && samples.length > 0) {
    const perPeak = samples.length / peak_count;
    // Read every sample of a short file, but at most ~50 per peak of a long
    // one: a peak only needs to catch the loud parts.
    const stride = Math.max(1, Math.floor(perPeak / 50));
    for (let p = 0; p < peak_count; p++) {
      const end = Math.min(Math.floor((p + 1) * perPeak), samples.length);
      let peak = 0;
      for (let i = Math.floor(p * perPeak); i < end; i += stride) {
        const v = Math.abs(samples[i]);
        if (v > peak) peak = v;
      }
      peaks.push(thousandths(peak));
    }
  }
  return new WireWriter().i64(Math.round(decoded.duration * 1000)).u16s(peaks);
});

//// op joy/media/object_url needs named
// The same file always gets the same URL.
const objectUrls = new Map(); // file id -> object URL
defineOperation('joy/media/object_url', (args, host) => {
  const file_id = args.u32();
  const file = host.file(file_id);
  if (!file) throw named('NotFoundError', 'no such file');
  let url = objectUrls.get(file_id);
  if (url === undefined) {
    url = URL.createObjectURL(file);
    objectUrls.set(file_id, url);
  }
  return new WireWriter().str(url);
});

//// helper media_element needs named
function mediaElement(selector, host) {
  const el = host.element(selector);
  if (!el) throw named('NotFoundError', `nothing on the page matches "${selector}"`);
  if (typeof el.play !== 'function') throw named('NotSupportedError', `"${selector}" is not an audio or video element`);
  return el;
}

//// op joy/media/play needs media_element
defineOperation('joy/media/play', async (args, host) => {
  await mediaElement(args.str(), host).play();
});

//// op joy/media/pause needs media_element
defineOperation('joy/media/pause', (args, host) => {
  mediaElement(args.str(), host).pause();
});

//// op joy/media/seek needs media_element
defineOperation('joy/media/seek', (args, host) => {
  const el = mediaElement(args.str(), host);
  el.currentTime = args.u64() / 1000;
});
