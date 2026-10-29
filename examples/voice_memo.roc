app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, p, button, text, element]
import html.Attribute exposing [id, on_click, src, attribute, on_property, on]
import pf.Effect
import pf.Media
import pf.Sub

# A voice memo: record from the microphone with a live level meter, then
# play the memo back and see its length and waveform.
#
# The microphone is open exactly while the app is asking for it or
# recording: `Media.stream` sits in the subscription list then and only
# then, so stopping (or failing) lets it go without any cleanup code. The
# finished recording is an ordinary file, the same kind a file input gives,
# so it could be uploaded with Http.request_file as it is.

Status : [
	Idle,
	Asking,
	Recording({ stream : Media.MediaStream, recorder : Media.MediaRecorder }),
	Finishing,
	Failed(Str),
]

Memo : {
	file : Attribute.FileInfo,
	url : Str,
	duration_ms : I64,
	peaks : List(U16),
}

Model : {
	status : Status,
	level : U16,
	memo : Try(Memo, [NoMemo]),
	position_ms : I64,
}

Msg : [
	UserClickedRecord,
	StreamOpened(Try(Media.MediaStream, Media.Problem)),
	RecordingStarted(Media.MediaStream, Try(Media.MediaRecorder, Media.Problem)),
	LevelSampled(U16),
	UserClickedStop,
	Finished(Try(Attribute.FileInfo, Media.Problem)),
	GotUrl(Try(Str, Media.Problem)),
	GotSummary(Try({ duration_ms : I64, peaks : List(U16) }, Media.Problem)),
	UserClickedPlay,
	UserClickedPause,
	UserClickedRewind,
	PlaybackMoved(Str),
	PlaybackDone(Try({}, Media.Problem)),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ status: Idle, level: 0, memo: Err(NoMemo), position_ms: 0 }, [])

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model| {
	microphone = Media.stream({ audio: Bool.True, video: Bool.False }, |opened| StreamOpened(opened))
	match model.status {
		Asking => [microphone]
		Recording({ stream, .. }) => [microphone, Media.levels(stream, 100, |level| LevelSampled(level))]
		Finishing => [microphone]
		_ => []
	}
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedRecord => ({ ..model, status: Asking, level: 0 }, [])

		StreamOpened(Ok(stream)) =>
			match model.status {
				Asking => (model, [Media.record(stream, { mime_type: "", min_audio_bits_per_second: 128_000 }, |started| RecordingStarted(stream, started))])
				_ => (model, [])
			}

		StreamOpened(Err(problem)) => ({ ..model, status: Failed(describe(problem)) }, [])

		RecordingStarted(stream, Ok(recorder)) => ({ ..model, status: Recording({ stream, recorder }) }, [])
		RecordingStarted(_, Err(problem)) => ({ ..model, status: Failed(describe(problem)) }, [])

		LevelSampled(level) => ({ ..model, level }, [])

		UserClickedStop =>
			match model.status {
				Recording({ recorder, .. }) => ({ ..model, status: Finishing }, [Media.finish(recorder, "memo", |file| Finished(file))])
				_ => (model, [])
			}

		Finished(Ok(file)) =>
			(
				{ ..model, status: Idle, memo: Ok({ file, url: "", duration_ms: 0, peaks: [] }), position_ms: 0 },
				[Media.object_url(file.id, |url| GotUrl(url)), Media.audio_summary(file.id, 20, |summary| GotSummary(summary))],
			)

		Finished(Err(problem)) => ({ ..model, status: Failed(describe(problem)) }, [])

		GotUrl(Ok(url)) => ({ ..model, memo: model.memo.map_ok(|memo| { ..memo, url }) }, [])
		GotSummary(Ok({ duration_ms, peaks })) => ({ ..model, memo: model.memo.map_ok(|memo| { ..memo, duration_ms, peaks }) }, [])
		GotUrl(Err(problem)) | GotSummary(Err(problem)) => ({ ..model, status: Failed(describe(problem)) }, [])

		UserClickedPlay => (model, [Media.play("#memo", |done| PlaybackDone(done))])
		UserClickedPause => (model, [Media.pause("#memo", |done| PlaybackDone(done))])
		UserClickedRewind => (model, [Media.seek("#memo", 0, |done| PlaybackDone(done))])

		# The element reports its position in seconds.
		PlaybackMoved(seconds) => ({ ..model, position_ms: ((F64.from_str(seconds) ?? 0.0) * 1000.0).round_to_i64_try() ?? 0 }, [])

		PlaybackDone(Ok({})) => (model, [])
		PlaybackDone(Err(problem)) => ({ ..model, status: Failed(describe(problem)) }, [])
	}

describe : Media.Problem -> Str
describe = |problem|
	match problem {
		NotAllowed => "microphone not allowed"
		NotFound => "no microphone"
		NotReadable => "microphone busy"
		Insecure => "needs a secure page"
		Unsupported => "not supported here"
		Other(why) => why
	}

render : Model -> Html.Html(Msg)
render = |model| {
	status =
		match model.status {
			Idle => "idle"
			Asking => "asking for the microphone"
			Recording(_) => "recording"
			Finishing => "finishing"
			Failed(why) => "failed: ${why}"
		}

	recording_controls =
		match model.status {
			Recording(_) => [button([id("stop"), on_click(UserClickedStop)], [text("Stop")])]
			Asking | Finishing => []
			_ => [button([id("record"), on_click(UserClickedRecord)], [text("Record")])]
		}

	memo_view =
		match model.memo {
			Err(NoMemo) => []
			Ok(memo) =>
				[
					p([id("memo-info")], [text("${memo.file.name}, ${memo.file.size.to_str()} bytes, ${memo.duration_ms.to_str()} ms, ${memo.peaks.len().to_str()} peaks")]),
					p([id("waveform")], [text(Str.join_with(memo.peaks.map(bar), ""))]),
					element(
						"audio",
						[
							id("memo"),
							src(memo.url),
							on_property("timeupdate", "currentTime", |seconds| PlaybackMoved(seconds)),
							on("ended", PlaybackMoved("0")),
							attribute("preload", "auto"),
						],
						[],
					),
					button([id("play"), on_click(UserClickedPlay)], [text("Play")]),
					button([id("pause"), on_click(UserClickedPause)], [text("Pause")]),
					button([id("rewind"), on_click(UserClickedRewind)], [text("Rewind")]),
					p([id("position")], [text("at ${model.position_ms.to_str()} ms")]),
				]
		}

	div(
		[],
		[
			p([id("status")], [text(status)]),
			p([id("level")], [text("level ${model.level.to_str()}")]),
		]
			.concat(recording_controls)
			.concat(memo_view),
	)
}

## One of eight block heights for a peak in thousandths.
bar : U16 -> Str
bar = |peak| {
	blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
	blocks.get((peak.to_u64() * 7 // 1000)) ?? "▁"
}
