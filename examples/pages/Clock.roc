## The clock page. It shows the two things a page can ask of the outside
## world: an effect at boot (a timer that fires right away, so the first
## render shows the time instead of waiting a whole second) and a recurring
## subscription (the tick every second). Both are returned as values, and
## app.roc maps them into its own Msg with Effect.map and Sub.map.
import html.Html exposing [Html, button, div, h2, li, p, text, ul]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]
import pf.Time

Clock := [].{
	## The time in ms since the Unix epoch, whether the clock is paused,
	## and the moments the user marked.
	Model : { now : I64, paused : Bool, laps : List(I64) }

	Msg : [
		Tick(I64),
		UserToggledPause,
		UserClickedLap,
		UserClearedLaps,
	]

	## The app is pure, so there is no clock to read at boot. A timer that
	## fires at once delivers the time as the first Tick instead.
	init : {} -> (Model, List(Effect(Msg)))
	init = |_| ({ now: 0, paused: Bool.False, laps: [] }, [Time.after(0, |t| Tick(t))])

	update : Model, Msg -> (Model, List(Effect(Msg)))
	update = |model, msg|
		match msg {
			Tick(t) => ({ ..model, now: t }, [])
			UserToggledPause => ({ ..model, paused: !model.paused }, [])
			UserClickedLap => ({ ..model, laps: model.laps.append(model.now) }, [])
			UserClearedLaps => ({ ..model, laps: [] }, [])
		}

	## Ticks keep coming while the page is mounted, whether or not it is the
	## one on screen, so the time is right the moment the user comes back.
	## Pausing drops the subscription, which stops the timer.
	subscriptions : Model -> List(Sub(Msg))
	subscriptions = |model|
		if model.paused {
			[]
		} else {
			[Time.every(1000, |t| Tick(t))]
		}

	view : Model -> Html(Msg)
	view = |model|
		div(
			[id("clock")],
			[
				h2([], [text("Clock")]),
				p([id("time")], [text(if model.now == 0 "..." else Clock.format(model.now))]),
				button([id("pause"), on_click(UserToggledPause)], [text(if model.paused "Resume" else "Pause")]),
				button([id("lap"), on_click(UserClickedLap)], [text("Lap")]),
				button([id("clear"), on_click(UserClearedLaps)], [text("Clear laps")]),
				ul([id("laps")], model.laps.map(|lap| li([], [text(Clock.format(lap))]))),
			],
		)

	## HH:MM:SS in UTC. The time is a plain integer, so the page turns it into
	## text itself, and that is the sort of pure transformation a page is for.
	format : I64 -> Str
	format = |ms| {
		seconds = ms // 1000
		hours = (seconds // 3600) % 24
		minutes = (seconds // 60) % 60
		"${Clock.pad(hours)}:${Clock.pad(minutes)}:${Clock.pad(seconds % 60)} UTC"
	}

	pad : I64 -> Str
	pad = |n| if n < 10 "0${n.to_str()}" else n.to_str()
}

expect Clock.format(0) == "00:00:00 UTC"
expect Clock.format(3_723_000) == "01:02:03 UTC"
expect Clock.format(86_399_000) == "23:59:59 UTC"
expect Clock.format(86_400_000) == "00:00:00 UTC"
