# An app split into pages where each page is its own URL: /counter, /clock
# and /notes are plain links, following one loads a new page, and the model
# holds only the page on screen. Leaving a page throws its state away. That
# is the shape of a server-rendered app the client hydrates, where the
# server picks the page from the path and each page starts fresh, so the
# path is what this app boots from too: the page passes location.pathname
# as the flags (see www/index.html).
#
# The page modules are the same as in examples/spa_pages/, which keeps every
# page's model alive and switches between them in place. Only this file
# differs, so the two are easy to compare.
app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import Clock
import Counter
import Notes
import html.Html exposing [a, div, main, nav, text]
import html.Attribute exposing [class_list, href, id]
import pf.Effect
import pf.Sub

# The page on screen, carrying that page's model and nothing else.
Model : [
	Counter(Counter.Model),
	Clock(Clock.Model),
	Notes(Notes.Model),
]

# One wrapper per page. Nothing switches pages from inside the app, the
# links do that, so there is no page-change message.
Msg : [
	CounterMsg(Counter.Msg),
	ClockMsg(Clock.Msg),
	NotesMsg(Notes.Msg),
]

# The path picks the page, and only that page's init runs. The last segment
# is looked at, so the app works at the root of a site and under a prefix
# alike. Anything unknown, including the root, is the counter.
init : Str -> (Model, List(Effect(Msg)))
init = |path|
	match last_segment(path) {
		"clock" => {
			(clock, effects) = Clock.init({})
			(Clock(clock), map_effects(effects, |m| ClockMsg(m)))
		}

		"notes" => {
			(notes, effects) = Notes.init({})
			(Notes(notes), map_effects(effects, |m| NotesMsg(m)))
		}

		_ => {
			(counter, effects) = Counter.init({})
			(Counter(counter), map_effects(effects, |m| CounterMsg(m)))
		}
	}

# A message only counts when it is for the page on screen. The arms match
# the page and the message together. Anything else, like a timer that
# fired after its page was left, is dropped.
update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match (model, msg) {
		(Counter(counter), CounterMsg(m)) => {
			(next, effects) = Counter.update(counter, m)
			(Counter(next), map_effects(effects, |cm| CounterMsg(cm)))
		}

		(Clock(clock), ClockMsg(m)) => {
			(next, effects) = Clock.update(clock, m)
			(Clock(next), map_effects(effects, |cm| ClockMsg(cm)))
		}

		(Notes(notes), NotesMsg(m)) => {
			(next, effects) = Notes.update(notes, m)
			(Notes(next), map_effects(effects, |nm| NotesMsg(nm)))
		}

		_ => (model, [])
	}

# Only the page on screen has subscriptions, since only it has a model.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	match model {
		Counter(counter) => map_subs(Counter.subscriptions(counter), |m| CounterMsg(m))
		Clock(clock) => map_subs(Clock.subscriptions(clock), |m| ClockMsg(m))
		Notes(notes) => map_subs(Notes.subscriptions(notes), |m| NotesMsg(m))
	}

view : Model -> Html(Msg)
view = |model| {
	page =
		match model {
			Counter(counter) => Html.map(Counter.view(counter), |m| CounterMsg(m))
			Clock(clock) => Html.map(Clock.view(clock), |m| ClockMsg(m))
			Notes(notes) => Html.map(Notes.view(notes), |m| NotesMsg(m))
		}

	div(
		[],
		[
			nav(
				[id("pages")],
				[
					page_link("Counter", "counter", model),
					page_link("Clock", "clock", model),
					page_link("Notes", "notes", model),
				],
			),
			main([], [page]),
		],
	)
}

# A real link. The href is relative, so it lands next to whatever URL the
# app is at, and the browser loads the page from scratch.
page_link : Str, Str, Model -> Html(Msg)
page_link = |label, path, model|
	a(
		[href(path), class_list([("current", path == page_name(model))])],
		[text(label)],
	)

page_name : Model -> Str
page_name = |model|
	match model {
		Counter(_) => "counter"
		Clock(_) => "clock"
		Notes(_) => "notes"
	}

# "clock" for "/clock", "/pages/clock" or "/pages/clock/", "" for "/".
last_segment : Str -> Str
last_segment = |path|
	match path.drop_suffix("/").split_last("/") {
		Ok(split) => split.after
		Err(_) => ""
	}

expect last_segment("/") == ""
expect last_segment("/clock") == "clock"
expect last_segment("/pages/clock") == "clock"
expect last_segment("/pages/notes/") == "notes"

# Wrap everything a page returns into the app's Msg. Effect.map and Sub.map
# work on one value, and a page returns lists, so these are the two lines
# every arm above would otherwise repeat.
map_effects : List(Effect(a)), (a -> Msg) -> List(Effect(Msg))
map_effects = |effects, wrap| effects.map(|effect| Effect.map(effect, wrap))

map_subs : List(Sub(a)), (a -> Msg) -> List(Sub(Msg))
map_subs = |subs, wrap| subs.map(|sub| Sub.map(sub, wrap))
