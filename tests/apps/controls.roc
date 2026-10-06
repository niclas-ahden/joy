app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [button, div, input, option, p, select, text]
import html.Attribute exposing [checked, id, on, on_change, on_check, on_click, on_input, type, value]
import pf.Effect

# Fixture for controlled form controls outside the simple case
# (tests/check_controls.mjs and tests/e2e/controls_test.roc):
#
#   * a select controlled by its own `value`, which names an option that
#     only exists once the select's children do, at boot and when the
#     options arrive in a later render
#   * value handlers on a wrapper rather than on the control, which see the
#     control's event as it bubbles: the update refuses "!" and unchecking
#     there too
#   * a search field whose messages are counted, so a value delivered twice
#     for one edit shows
#   * a field listening for `select` whose value the model rewrites while
#     another element has focus, which must neither select nor focus it
#   * a field committed on change inside a wrapper that handles clicks: a
#     click that bubbles through the field must not undo what was typed
#   * a select naming a value that only one option's later attribute patch
#     gives it, which must then show that option

Model : {
	level : Str,
	loaded : Bool,
	query : Str,
	agreed : Bool,
	search : Str,
	searches : U64,
	title : Str,
	renames : U64,
	selects : U64,
	note : Str,
	note_clicks : U64,
	swapped : Bool,
}

Msg : [
	UserPickedLevel(Str),
	UserClickedLoad,
	UserTypedQuery(Str),
	UserToggledAgree(Bool),
	UserSearched(Str),
	UserClickedRename,
	UserSelectedTitle,
	UserClickedNoteBox,
	UserChangedNote(Str),
	UserClickedSwap,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (
	{
		level: "high",
		loaded: Bool.False,
		query: "",
		agreed: Bool.True,
		search: "",
		searches: 0,
		title: "Draft",
		renames: 0,
		selects: 0,
		note: "",
		note_clicks: 0,
		swapped: Bool.False,
	},
	[],
)

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserPickedLevel(level) => ({ ..model, level }, [])
		UserClickedLoad => ({ ..model, loaded: Bool.True }, [])
		UserTypedQuery(query) => if query.contains("!") (model, []) else ({ ..model, query }, [])
		UserToggledAgree(now) => if now ({ ..model, agreed: Bool.True }, []) else (model, [])
		UserSearched(search) => ({ ..model, search, searches: model.searches + 1 }, [])
		UserClickedRename => {
			renames = model.renames + 1
			({ ..model, title: "Renamed ${renames.to_str()}", renames }, [])
		}

		UserSelectedTitle => ({ ..model, selects: model.selects + 1 }, [])
		UserClickedNoteBox => ({ ..model, note_clicks: model.note_clicks + 1 }, [])
		UserChangedNote(note) => ({ ..model, note }, [])
		UserClickedSwap => ({ ..model, swapped: Bool.True }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	levels = ["low", "medium", "high"].map(|l| option([value(l)], [text(l)]))
	div(
		[],
		[
			select([id("level"), value(model.level), on_change(|l| UserPickedLevel(l))], levels),
			select([id("late"), value(model.level), on_change(|l| UserPickedLevel(l))], if model.loaded levels else []),
			button([id("load"), on_click(UserClickedLoad)], [text("Load")]),
			div([id("query-box"), on_input(|s| UserTypedQuery(s))], [input([id("query"), value(model.query)])]),
			div([id("agree-box"), on_check(|now| UserToggledAgree(now))], [input([id("agree"), type("checkbox"), checked(model.agreed)])]),
			input([id("search"), value(model.search), on_input(|s| UserSearched(s))]),
			p([id("searches")], [text("searches ${model.searches.to_str()}")]),
			input([id("title"), value(model.title), on("select", UserSelectedTitle)]),
			button([id("rename"), on_click(UserClickedRename)], [text("Rename")]),
			p([id("selects")], [text("selects ${model.selects.to_str()}")]),
			div([id("note-box"), on_click(UserClickedNoteBox)], [input([id("note"), value(model.note), on_change(|s| UserChangedNote(s))])]),
			p([id("note-clicks")], [text("note clicks ${model.note_clicks.to_str()}")]),
			select([id("swap"), value("b")], [option([value(if model.swapped "b" else "c")], [text("first")]), option([value("a")], [text("second")])]),
			button([id("swap-button"), on_click(UserClickedSwap)], [text("Swap")]),
		],
	)
}
