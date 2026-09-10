## The notes page. The most stateful of the three: a draft being typed, the
## notes kept so far, and a search that filters what is shown. The page is
## pure: nothing here needs the outside world, so update never returns an
## effect. Compare Clock.roc, which does.
import html.Html exposing [Html, button, div, h2, input, li, p, span, text, ul]
import html.Attribute exposing [id, on_click, on_input, on_key, placeholder, value]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]

Notes := [].{
	Note : { id : U64, body : Str }

	## Ids only ever go up, so deleting a note never lets a later one reuse
	## its id, and the list is keyed on them below.
	Model : { draft : Str, search : Str, notes : List(Note), next_id : U64 }

	Msg : [
		UserTypedDraft(Str),
		UserSubmittedDraft,
		UserTypedSearch(Str),
		UserClickedDelete(U64),
		UserClearedNotes,
	]

	init : {} -> (Model, List(Effect(Msg)))
	init = |_| ({ draft: "", search: "", notes: [], next_id: 1 }, [])

	update : Model, Msg -> (Model, List(Effect(Msg)))
	update = |model, msg|
		match msg {
			UserTypedDraft(draft) => ({ ..model, draft }, [])

			# A blank draft is ignored. Otherwise the trimmed text becomes a
			# note and the field empties.
			UserSubmittedDraft => {
				body = model.draft.trim()
				if body.is_empty() {
					(model, [])
				} else {
					note = { id: model.next_id, body }
					({ ..model, draft: "", notes: model.notes.append(note), next_id: model.next_id + 1 }, [])
				}
			}

			UserTypedSearch(search) => ({ ..model, search }, [])

			UserClickedDelete(note_id) =>
				({ ..model, notes: model.notes.keep_if(|note| note.id != note_id) }, [])

			UserClearedNotes => ({ ..model, notes: [], search: "" }, [])
		}

	subscriptions : Model -> List(Sub(Msg))
	subscriptions = |_model| []

	## The notes matching the search, or all of them when the search is
	## blank.
	visible : Model -> List(Note)
	visible = |model|
		if model.search.is_empty() {
			model.notes
		} else {
			model.notes.keep_if(|note| note.body.contains(model.search))
		}

	view : Model -> Html(Msg)
	view = |model| {
		shown = Notes.visible(model)
		div(
			[id("notes")],
			[
				h2([], [text("Notes")]),
				input(
					[
						id("draft"),
						placeholder("Write a note and press Enter"),
						value(model.draft),
						on_input(|s| UserTypedDraft(s)),
						on_key("keydown", ["Enter"], |_| UserSubmittedDraft).prevent_default(),
					],
				),
				button([id("add"), on_click(UserSubmittedDraft)], [text("Add")]),
				button([id("clear"), on_click(UserClearedNotes)], [text("Clear all")]),
				p(
					[],
					[
						input([id("search"), placeholder("Search"), value(model.search), on_input(|s| UserTypedSearch(s))]),
						span([id("summary")], [text(" ${shown.len().to_str()} of ${model.notes.len().to_str()} shown")]),
					],
				),
				# Keyed on the id, so deleting a note in the middle moves the
				# rows below it instead of rewriting each of them.
				ul(
					[id("list")],
					shown.map(
						|note| Html.keyed(
							note.id.to_str(),
							li(
								[],
								[
									text(note.body),
									button([on_click(UserClickedDelete(note.id))], [text("x")]),
								],
							),
						),
					),
				),
			],
		)
	}
}
