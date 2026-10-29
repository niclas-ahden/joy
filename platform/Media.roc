## Audio and video in the browser: capture from a microphone or camera,
## loudness while capturing, recording to a file, an audio file's length and
## waveform, and playback of `<audio>` and `<video>` elements.
##
## A capture is a subscription: the microphone or camera is open exactly while
## `stream` is in the app's subscription list, and leaving it out stops the
## tracks, so the browser's recording indicator goes out and nothing is left
## running. A recording is an effect on an open stream and finishes into an
## ordinary file, the same `Attribute.FileInfo` a file input gives, so
## `Http.request_file`, `WebCrypto.digest_file_slice` and `object_url` take it
## as they take a picked file.
##
## A voice memo, from the microphone to a file:
##
## ```
## subscriptions = |model|
##     if model.recording [Media.stream({ audio: Bool.True, video: Bool.False }, |opened| StreamOpened(opened))] else []
##
## update = |model, msg|
##     match msg {
##         UserClickedRecord => ({ ..model, recording: Bool.True }, [])
##         StreamOpened(Ok(stream)) => (model, [Media.record(stream, Media.default_recording, |r| RecordingStarted(r))])
##         StreamOpened(Err(problem)) => ({ ..model, recording: Bool.False, problem: Ok(problem) }, [])
##         RecordingStarted(Ok(recorder)) => ({ ..model, recorder: Ok(recorder) }, [])
##         UserClickedStop => (model, model.recorder.map_ok(|r| [Media.finish(r, "memo", |f| Finished(f))]) ?? [])
##         Finished(Ok(file)) => ({ ..model, recording: Bool.False, memo: Ok(file) }, [])
##         ...
##     }
## ```
##
## Handles are plain records, so a model holding one still encodes as JSON.
## Media needs a secure page: HTTPS, or localhost while developing.
import html.Attribute
import Effect
import Sub
import Wire

Media := [].{
	## An open microphone or camera, from `stream`. The browser's `MediaStream`.
	MediaStream : { stream_id : U32 }

	## A recording in progress, from `record`. The browser's `MediaRecorder`.
	MediaRecorder : { recorder_id : U32 }

	## Why the browser said no. `NotAllowed` is the user or the browser
	## refusing access, which only the browser's own settings can undo once
	## refused. `NotFound` is no such device, `NotReadable` a device another
	## program holds or the system blocks, `Insecure` a page that is not
	## HTTPS (or localhost), and `Unsupported` a browser without the API or
	## the format asked for.
	Problem : [NotAllowed, NotFound, NotReadable, Insecure, Unsupported, Other(Str)]

	## What to record: a container (`"audio/webm"`, say, or `""` for the
	## browser's choice, Opus in webm where it can and mp4 in Safari) and the
	## lowest audio bitrate to accept. A browser that would record lower is
	## raised to it, and one that already records higher keeps its own.
	RecordingOptions : { mime_type : Str, min_audio_bits_per_second : U32 }

	default_recording : RecordingOptions
	default_recording = { mime_type: "", min_audio_bits_per_second: 0 }

	## Open the microphone (`audio`), the camera (`video`) or both, while
	## subscribed. The browser asks the user first, so the answer can come
	## much later. A changed request is a new stream: the old one closes and
	## the new one asks again.
	stream : { audio : Bool, video : Bool }, (Try(Media.MediaStream, Media.Problem) -> msg) -> Sub(msg)
	stream = |{ audio, video }, on_open|
		Sub.listen("joy/media/stream", Wire.writer({}).bool(audio).bool(video).done(), |event| on_open(opened(event)))

	## How loud the stream is: the loudest sample since the last report, in
	## thousandths of full scale, every `interval_ms`, while subscribed. For a
	## level meter or a live waveform.
	levels : Media.MediaStream, U32, (U16 -> msg) -> Sub(msg)
	levels = |{ stream_id }, interval_ms, on_level|
		Sub.listen(
			"joy/media/levels",
			Wire.writer({}).u32(stream_id).u32(interval_ms).done(),
			|event| on_level(Wire.reader(event).u16().map_ok(|(level, _)| level) ?? 0),
		)

	## Start recording an open stream. Stopping the stream discards a
	## recording that was not finished.
	record : Media.MediaStream, Media.RecordingOptions, (Try(Media.MediaRecorder, Media.Problem) -> msg) -> Effect(msg)
	record = |{ stream_id }, { mime_type, min_audio_bits_per_second }, on_start|
		Effect.call(
			"joy/media/record",
			Wire.writer({}).u32(stream_id).str(mime_type).u32(min_audio_bits_per_second).done(),
			|reply| on_start(answer(reply, |r| r.u32().map_ok(|(recorder_id, _)| { recorder_id: recorder_id }))),
		)

	## Stop a recording and hand it over as a file named `<name>.<extension>`,
	## the extension following the container the browser recorded in.
	finish : Media.MediaRecorder, Str, (Try(Attribute.FileInfo, Media.Problem) -> msg) -> Effect(msg)
	finish = |{ recorder_id }, name, on_file|
		Effect.call(
			"joy/media/finish",
			Wire.writer({}).u32(recorder_id).str(name).done(),
			|reply| on_file(answer(reply, file_info)),
		)

	## A browser-held audio file's length and its waveform as `peak_count`
	## peaks in thousandths of full scale, evenly spread over it. The audio
	## is decoded where it is, its bytes never enter the app.
	audio_summary : U32, U64, (Try({ duration_ms : I64, peaks : List(U16) }, Media.Problem) -> msg) -> Effect(msg)
	audio_summary = |file_id, peak_count, on_summary|
		Effect.call(
			"joy/media/audio_summary",
			Wire.writer({}).u32(file_id).u32(peak_count.to_u32_wrap()).done(),
			|reply| on_summary(answer(reply, summary)),
		)

	## A URL for a browser-held file, to use as an `<audio>`, `<video>` or
	## `<img>` element's `src`. The same file always gets the same URL.
	object_url : U32, (Try(Str, Media.Problem) -> msg) -> Effect(msg)
	object_url = |file_id, on_url|
		Effect.call(
			"joy/media/object_url",
			Wire.writer({}).u32(file_id).done(),
			|reply| on_url(answer(reply, |r| r.str().map_ok(|(url, _)| url))),
		)

	## Play the `<audio>` or `<video>` element the selector names. Browsers
	## refuse to play with sound before the user has interacted with the
	## page, which arrives as `NotAllowed`.
	play : Str, (Try({}, Media.Problem) -> msg) -> Effect(msg)
	play = |selector, on_done| Effect.call("joy/media/play", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))

	## Pause the `<audio>` or `<video>` element the selector names.
	pause : Str, (Try({}, Media.Problem) -> msg) -> Effect(msg)
	pause = |selector, on_done| Effect.call("joy/media/pause", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))

	## Move the `<audio>` or `<video>` element the selector names to
	## `position_ms`.
	seek : Str, U64, (Try({}, Media.Problem) -> msg) -> Effect(msg)
	seek = |selector, position_ms, on_done|
		Effect.call("joy/media/seek", Wire.writer({}).str(selector).u64(position_ms).done(), |reply| on_done(done(reply)))
}

## A stream event: 0 and the stream's id once it is open, or 1 and the name
## of the error the browser refused with.
opened : List(U8) -> Try(Media.MediaStream, Media.Problem)
opened = |event| {
	r = Wire.reader(event)
	match r.u8() {
		Ok((0, rest)) => rest.u32().map_ok(|(stream_id, _)| { stream_id: stream_id }).map_err(|_| Other("unreadable stream"))
		Ok((_, rest)) => Err(problem_named(rest.str().map_ok(|(name, _)| name) ?? ""))
		Err(_) => Err(Other("unreadable stream"))
	}
}

## A reply's answer, read with `read`, or the reason it failed.
answer : List(U8), (Wire.Reader -> Try(a, [WireEnded])) -> Try(a, Media.Problem)
answer = |reply, read| {
	bytes = Effect.reply(reply).map_err(problem)?
	read(Wire.reader(bytes)).map_err(|_| Other("unreadable answer"))
}

done : List(U8) -> Try({}, Media.Problem)
done = |reply| Effect.reply(reply).map_ok(|_| {}).map_err(problem)

file_info : Wire.Reader -> Try(Attribute.FileInfo, [WireEnded])
file_info = |r| {
	(id, r1) = r.u32()?
	(name, r2) = r1.str()?
	(mime, r3) = r2.str()?
	(size, _) = r3.u64()?
	Ok({ id, name, mime, size })
}

summary : Wire.Reader -> Try({ duration_ms : I64, peaks : List(U16) }, [WireEnded])
summary = |r| {
	(duration_ms, r1) = r.i64()?
	(peaks, _) = r1.u16s()?
	Ok({ duration_ms, peaks })
}

## A failed reply's reason starts with the browser's error name, the way the
## media feature reports it: "NotAllowedError: Permission denied".
problem : [FeatureFailed(Str)] -> Media.Problem
problem = |FeatureFailed(reason)| problem_named(reason.split_first(":").map_ok(|parts| parts.before) ?? reason)

problem_named : Str -> Media.Problem
problem_named = |name|
	match name.trim() {
		"NotAllowedError" => NotAllowed
		"NotFoundError" => NotFound
		"NotReadableError" => NotReadable
		"SecurityError" => Insecure
		"NotSupportedError" => Unsupported
		other => Other(other)
	}

expect opened(Wire.writer({}).u8(0).u32(3).done()) == Ok({ stream_id: 3 })
expect opened(Wire.writer({}).u8(1).str("NotAllowedError").done()) == Err(NotAllowed)
expect problem(FeatureFailed("NotSupportedError: no such container")) == Unsupported
expect problem_named("NotFoundError") == NotFound
expect answer([0].concat(Wire.writer({}).i64(1500).u32(3).u16(0).u16(500).u16(1000).done()), summary) == Ok({ duration_ms: 1500, peaks: [0, 500, 1000] })
expect answer([1].concat(Str.to_utf8("NotAllowedError: no")), file_info) == Err(NotAllowed)
