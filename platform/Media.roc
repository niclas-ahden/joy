## Record from the microphone or the camera, and play audio and video.
##
## ## Recording
##
## Three steps take you from the microphone to a file.
##
## Open the microphone with [Media.stream]. It is a subscription, so the
## microphone is open exactly while it is in the list `subscriptions` returns:
##
## ```roc
## microphone = { audio: Bool.True, video: Bool.False }
##
## subscriptions = |model|
##     if model.recording {
##         [Media.stream(microphone, |s| StreamOpened(s))]
##     } else {
##         []
##     }
## ```
##
## When it has opened, start recording with [Media.record]:
##
## ```roc
## StreamOpened(Ok(stream)) =>
##     (
##         model,
##         [
##             Media.record(
##                 stream,
##                 Media.default_recording,
##                 |r| RecorderStarted(r),
##             ),
##         ],
##     )
## ```
##
## To stop, call [Media.finish]. It hands you the recording as a file:
##
## ```roc
## Media.finish(recorder, "memo", |file| RecordingDone(file))
## ```
##
## That file is like one from a file input. You can upload it with
## [Http.post_file], hash it with [WebCrypto.digest_file], or play it back
## through [Media.object_url].
##
## Leave the stream out of `subscriptions` and the microphone closes: the
## browser's recording sign goes out, and nothing is left running.
##
## ## Good to know
##
## - Media needs a secure page: HTTPS, or localhost while you develop.
## - The browser asks the user before it opens a microphone or a camera, so
##   the answer can take a while.
## - A stream and a recorder are plain records, so your model can hold them.
##
## The repository has [a voice memo example](https://github.com/niclas-ahden/joy/blob/main/examples/voice_memo.roc)
## that records, shows the loudness and plays the memo back.
import html.Attribute
import Effect
import Sub
import Wire

Media := [].{

	## An open microphone or camera, from [Media.stream].
	MediaStream : { stream_id : U32 }

	## A recording that is under way, from [Media.record].
	MediaRecorder : { recorder_id : U32 }

	## Why it did not work.
	##
	## - `NotAllowed`: the user or the browser said no. Once refused, only the
	##   browser's own settings can change it.
	## - `NotFound`: there is no such device.
	## - `NotReadable`: another program holds the device, or the system blocks
	##   it.
	## - `Insecure`: the page is not served over HTTPS (or from localhost).
	## - `Unsupported`: the browser lacks the feature, or the format you asked
	##   for.
	## - `Other(name)`: anything else, with the browser's name for the error.
	Problem : [NotAllowed, NotFound, NotReadable, Insecure, Unsupported, Other(Str)]

	## How to record.
	##
	## - `mime_type` is the format, like `"audio/webm"`. `""` lets the browser
	##   choose: Opus in WebM where it can, and MP4 in Safari.
	## - `min_audio_bits_per_second` is the lowest audio quality you accept. A
	##   browser that would record lower is raised to it, and one that records
	##   higher keeps its own.
	RecordingOptions : { mime_type : Str, min_audio_bits_per_second : U32 }

	## The browser's own choice of format and quality. Start from it:
	##
	## ```roc
	## { ..Media.default_recording, mime_type: "audio/webm" }
	## ```
	default_recording : RecordingOptions
	default_recording = { mime_type: "", min_audio_bits_per_second: 0 }

	## Open the microphone (`audio`), the camera (`video`) or both, for as long as
	## the subscription is in the list `subscriptions` returns.
	##
	## ```roc
	## Media.stream(
	##     { audio: Bool.True, video: Bool.False },
	##     |opened| StreamOpened(opened),
	## )
	## ```
	##
	## The browser asks the user first, so the message can come much later.
	## Asking for something else, like adding the camera, is a new stream: the old
	## one closes, and the browser asks again.
	stream : { audio : Bool, video : Bool }, (Try(Media.MediaStream, Media.Problem) -> msg) -> Sub(msg)
	stream = |{ audio, video }, on_open|
		Sub.listen("joy/media/stream", Wire.writer({}).bool(audio).bool(video).done(), |event| on_open(opened(event)))

	## How loud an open stream is, every `interval_ms` milliseconds. Use it for a
	## level meter or a live waveform.
	##
	## ```roc
	## Media.levels(stream, 50, |level| MicLevel(level))
	## ```
	##
	## The level is the loudest moment since the last message, from 0 for silence
	## to 1000 for as loud as the device can go.
	levels : Media.MediaStream, U32, (U16 -> msg) -> Sub(msg)
	levels = |{ stream_id }, interval_ms, on_level|
		Sub.listen(
			"joy/media/levels",
			Wire.writer({}).u32(stream_id).u32(interval_ms).done(),
			|event| on_level(Wire.reader(event).u16().map_ok(|(level, _)| level) ?? 0),
		)

	## Start recording an open stream.
	##
	## ```roc
	## Media.record(
	##     stream,
	##     Media.default_recording,
	##     |started| RecorderStarted(started),
	## )
	## ```
	##
	## A recording that is not finished when its stream closes is thrown away.
	record : Media.MediaStream, Media.RecordingOptions, (Try(Media.MediaRecorder, Media.Problem) -> msg) -> Effect(msg)
	record = |{ stream_id }, { mime_type, min_audio_bits_per_second }, on_start|
		Effect.call(
			"joy/media/record",
			Wire.writer({}).u32(stream_id).str(mime_type).u32(min_audio_bits_per_second).done(),
			|reply| on_start(answer(reply, |r| r.u32().map_ok(|(recorder_id, _)| { recorder_id: recorder_id }))),
		)

	## Stop a recording and get it as a file.
	##
	## ```roc
	## Media.finish(recorder, "memo", |file| RecordingDone(file))
	## ```
	##
	## The file is named after `name`, with the ending of the format the browser
	## recorded in, like `memo.webm`.
	finish : Media.MediaRecorder, Str, (Try(Attribute.FileInfo, Media.Problem) -> msg) -> Effect(msg)
	finish = |{ recorder_id }, name, on_file|
		Effect.call(
			"joy/media/finish",
			Wire.writer({}).u32(recorder_id).str(name).done(),
			|reply| on_file(answer(reply, file_info)),
		)

	## The length of an audio file and its waveform, for a file the browser holds,
	## like a finished recording or a picked file.
	##
	## ```roc
	## Media.audio_summary(file.id, 200, |s| GotWaveform(s))
	## ```
	##
	## `peak_count` is how many points you want the waveform in. Each peak is the
	## loudest moment of its stretch, from 0 to 1000, and the stretches are spread
	## evenly over the file. The file's bytes never enter your app.
	audio_summary : U32, U64, (Try({ duration_ms : I64, peaks : List(U16) }, Media.Problem) -> msg) -> Effect(msg)
	audio_summary = |file_id, peak_count, on_summary|
		Effect.call(
			"joy/media/audio_summary",
			Wire.writer({}).u32(file_id).u32(peak_count.to_u32_wrap()).done(),
			|reply| on_summary(answer(reply, summary)),
		)

	## A URL for a file the browser holds, to give an `<audio>`, `<video>` or
	## `<img>` element as its `src`.
	##
	## ```roc
	## Media.object_url(file.id, |url| GotMemoUrl(url))
	## ```
	##
	## The same file always gets the same URL.
	object_url : U32, (Try(Str, Media.Problem) -> msg) -> Effect(msg)
	object_url = |file_id, on_url|
		Effect.call(
			"joy/media/object_url",
			Wire.writer({}).u32(file_id).done(),
			|reply| on_url(answer(reply, |r| r.str().map_ok(|(url, _)| url))),
		)

	## Play an `<audio>` or `<video>` element, found by a CSS selector. The
	## selector looks in your app's own view first, and then in the rest of the
	## page.
	##
	## ```roc
	## Media.play("#memo", |done| PlayStarted(done))
	## ```
	##
	## Browsers refuse to play sound before the user has clicked or typed
	## somewhere on the page. That comes back as `NotAllowed`.
	play : Str, (Try({}, Media.Problem) -> msg) -> Effect(msg)
	play = |selector, on_done| Effect.call("joy/media/play", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))

	## Pause an `<audio>` or `<video>` element.
	##
	## ```roc
	## Media.pause("#memo", |done| PlayPaused(done))
	## ```
	pause : Str, (Try({}, Media.Problem) -> msg) -> Effect(msg)
	pause = |selector, on_done| Effect.call("joy/media/pause", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))

	## Move an `<audio>` or `<video>` element to a position, in milliseconds from
	## its start.
	##
	## ```roc
	## Media.seek("#memo", 30_000, |done| PlayMoved(done))
	## ```
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
answer : List(U8), (Wire.Reader -> Try(a, Wire.Problem)) -> Try(a, Media.Problem)
answer = |reply, read| {
	bytes = Effect.reply(reply).map_err(problem)?
	read(Wire.reader(bytes)).map_err(|_| Other("unreadable answer"))
}

done : List(U8) -> Try({}, Media.Problem)
done = |reply| Effect.reply(reply).map_ok(|_| {}).map_err(problem)

file_info : Wire.Reader -> Try(Attribute.FileInfo, Wire.Problem)
file_info = |r| {
	(id, r1) = r.u32()?
	(name, r2) = r1.str()?
	(mime, r3) = r2.str()?
	(size, _) = r3.u64()?
	Ok({ id, name, mime, size })
}

summary : Wire.Reader -> Try({ duration_ms : I64, peaks : List(U16) }, Wire.Problem)
summary = |r| {
	(duration_ms, r1) = r.i64()?
	(peaks, _) = r1.u16s()?
	Ok({ duration_ms, peaks })
}

## A failed reply has the browser's error name, the way the media's
## JavaScript reports it: NotAllowedError when permission is denied.
problem : [EffectFailed({ name : Str, message : Str })] -> Media.Problem
problem = |EffectFailed({ name, .. })| problem_named(name)

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
expect problem(EffectFailed({ name: "NotSupportedError", message: "no such container" })) == Unsupported
expect problem_named("NotFoundError") == NotFound
expect answer([0].concat(Wire.writer({}).i64(1500).u16s([0, 500, 1000]).done()), summary) == Ok({ duration_ms: 1500, peaks: [0, 500, 1000] })
expect answer([1].concat(Str.to_utf8("NotAllowedError: no")), file_info) == Err(NotAllowed)
