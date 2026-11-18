import /Notebook
import /Route
import html.Html exposing [a, button, div, form, h1, hr, input, label, li, p, text, ul]
import html.Attribute exposing [aria, class, for_, href, id, on_click, on_input, on_submit, type, value]
import pf.DOM
import pf.Effect
import pf.Keyboard
import pf.Sub
import pf.Time

## List notes, with a form to add new ones, and to search (filter) them.
##
## `draft` holds the text in the "A new note" input.
## `typed` holds the text in the "Search" input.
## `query` holds what's currently being searched for. It can
##         differ from `typed` since we have debouncing.
##
## These three fields belong to the page itself, not the app,
## so that they're cleared whenever you navigate away.
## Notice that the `notebook` belongs to the *app*, though, so
## that all your notes remain regardless of what page you're on.
## That's why `update` and `view` are handed the notebook.
Notes := { draft : Str, typed : Str, query : Str }.{
	Msg : [
		UserTypedNote(Str),
		UserSubmittedNote,
		UserTypedSearch(Str),
		TypingPaused,
		UserPressedEscape,
		UserClickedClear,
	]

	init : Notes
	init = Notes.{ draft: "", typed: "", query: "" }

	update : Notes, Msg, Notebook -> (Notes, Notebook, List(Effect(Msg)))
	update = |model, msg, notebook|
		match msg {
			UserTypedNote(draft) => ({ ..model, draft }, notebook, [])

			UserSubmittedNote =>
				match notebook.add(model.draft) {
					Ok(added) => ({ ..model, draft: "" }, added, [])
					Err(Blank) => (model, notebook, [])
				}

			# Wait until you've stopped typing for 300 ms before searching
			# (debouncing).
			UserTypedSearch(typed) => ({ ..model, typed }, notebook, [Time.debounce("search", 300, |_now| TypingPaused)])
			TypingPaused => ({ ..model, query: model.typed }, notebook, [])

			# Cancel a search that's still waiting.
			UserPressedEscape => ({ ..model, typed: "", query: "" }, notebook, [Time.cancel("search")])

			# The same, and put the cursor back in the "Search" input.
			UserClickedClear =>
				({ ..model, typed: "", query: "" }, notebook, [Time.cancel("search"), DOM.focus("#search")])
		}

	## Listen for Escape to clear the search, but only while there's
	## something to clear.
	subscriptions : Notes -> List(Sub(Msg))
	subscriptions = |model|
		if model.typed.is_empty() {
			[]
		} else {
			[Keyboard.on_down_keys(["Escape"], |_key| UserPressedEscape)]
		}

	view : Notes, Notebook -> Html(Msg)
	view = |model, notebook| {
		found = notebook.matching(model.query)
		div(
			[],
			[
				h1([], [text("Notes")]),
				form(
					[class("field"), on_submit(UserSubmittedNote)],
					[
						label([for_("note")], [text("A new note")]),
						input([id("note"), value(model.draft), on_input(|typed| UserTypedNote(typed))]),
						button([type("submit")], [text("Add")]),
					],
				),
				hr([]),
				div(
					[class("field")],
					[
						label([for_("search")], [text("Search")]),
						input([id("search"), type("search"), value(model.typed), on_input(|typed| UserTypedSearch(typed))]),
						button([on_click(UserClickedClear)], [text("Clear")]),
					],
				),
				p([aria("live", "polite")], [text("${found.len().to_str()} of ${notebook.count().to_str()} notes")]),
				ul(
					[class("notes")],
					found.map(|note| Html.keyed(note.id.to_str(), li([], [a([href(Route.to_path(Note(note.id)))], [text(note.text)])]))),
				),
			],
		)
	}
}
