# A single-page app split into pages, each in a module of its own with its
# own Model, Msg, init, update, view and subscriptions.
#
# The pages switch in place, with a button per page, and every page's model
# stays around while another one is on screen. For the other shape, where
# each page is its own URL and the model holds only the page on screen, see
# examples/pages/.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import Clock
import Counter
import Notes
import html.Html exposing [button, div, main, nav, text]
import html.Attribute exposing [class_list, id, on_click]
import pf.Effect
import pf.Sub

Page : [Counter, Clock, Notes]

Model : {
	page : Page,
	counter : Counter.Model,
	clock : Clock.Model,
	notes : Notes.Model,
}

# One wrapper per page. A page's own Msg never reaches the platform on its
# own: the views, effects and subscriptions are all mapped into these, and
# `update` unwraps them to find the page to hand the message to.
Msg : [
	UserClickedPage(Page),
	CounterMsg(Counter.Msg),
	ClockMsg(Clock.Msg),
	NotesMsg(Notes.Msg),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| {
	(counter, counter_effects) = Counter.init({})
	(clock, clock_effects) = Clock.init({})
	(notes, notes_effects) = Notes.init({})
	(
		{ page: Counter, counter, clock, notes },
		[
			map_effects(counter_effects, |m| CounterMsg(m)),
			map_effects(clock_effects, |m| ClockMsg(m)),
			map_effects(notes_effects, |m| NotesMsg(m)),
		].join(),
	)
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedPage(page) => ({ ..model, page }, [])

		# Each arm is the same three steps: run the page's update on its
		# slice of the model, put the new slice back, and map the page's
		# effects into the app's Msg.
		CounterMsg(m) => {
			(counter, effects) = Counter.update(model.counter, m)
			({ ..model, counter }, map_effects(effects, |cm| CounterMsg(cm)))
		}

		ClockMsg(m) => {
			(clock, effects) = Clock.update(model.clock, m)
			({ ..model, clock }, map_effects(effects, |cm| ClockMsg(cm)))
		}

		NotesMsg(m) => {
			(notes, effects) = Notes.update(model.notes, m)
			({ ..model, notes }, map_effects(effects, |nm| NotesMsg(nm)))
		}
	}

# Every page's subscriptions, whichever page is showing: the clock keeps
# ticking on the counter page, so it is right when the user comes back.
# An app that wants only the visible page's subscriptions matches on
# `model.page` here instead.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	[
		map_subs(Counter.subscriptions(model.counter), |m| CounterMsg(m)),
		map_subs(Clock.subscriptions(model.clock), |m| ClockMsg(m)),
		map_subs(Notes.subscriptions(model.notes), |m| NotesMsg(m)),
	].join()

view : Model -> Html(Msg)
view = |model| {
	# The page's view produces Html(Counter.Msg) and so on. Html.map turns
	# it into Html(Msg), which is what lets the app's view return it.
	page =
		match model.page {
			Counter => Html.map(Counter.view(model.counter), |m| CounterMsg(m))
			Clock => Html.map(Clock.view(model.clock), |m| ClockMsg(m))
			Notes => Html.map(Notes.view(model.notes), |m| NotesMsg(m))
		}

	div(
		[],
		[
			nav(
				[id("pages")],
				[
					page_link("Counter", Counter, model.page),
					page_link("Clock", Clock, model.page),
					page_link("Notes", Notes, model.page),
				],
			),
			main([], [page]),
		],
	)
}

page_link : Str, Page, Page -> Html(Msg)
page_link = |label, page, current|
	button(
		[class_list([("current", page == current)]), on_click(UserClickedPage(page))],
		[text(label)],
	)

# Wrap everything a page returns into the app's Msg. Effect.map and Sub.map
# work on one value, and a page returns lists, so these are the two lines
# every arm above would otherwise repeat.
map_effects : List(Effect(a)), (a -> Msg) -> List(Effect(Msg))
map_effects = |effects, wrap| effects.map(|effect| Effect.map(effect, wrap))

map_subs : List(Sub(a)), (a -> Msg) -> List(Sub(Msg))
map_subs = |subs, wrap| subs.map(|sub| Sub.map(sub, wrap))
