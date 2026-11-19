import /Notebook
import /Route
import html.Html exposing [a, button, div, h1, p, text]
import html.Attribute exposing [href, on_click]
import pf.Effect
import pf.Navigation

## Show a single note, with a button to remove it.
##
## `id` holds which note to show. It comes from the URL, e.g. `/notes/3`.
##
## The notebook belongs to the *app*, so removing a note here removes it
## everywhere. That's why `update` and `view` are handed the notebook.
Note := { id : U64 }.{
	Msg : [UserClickedRemove]

	init : U64 -> Note
	init = |id| Note.{ id: id }

	## Once the note is removed there's nothing left to show, so we go back
	## to the list. To navigate we only change the URL. The app notices (see
	## `on_url_change` in app.roc) and shows the page.
	##
	## `Navigation.replace_url` is like `Navigation.push_url`, but it takes the place of
	## the current URL in the history. That way Back doesn't lead to the note
	## we just removed.
	update : Note, Msg, Notebook -> (Note, Notebook, List(Effect(Msg)))
	update = |model, msg, notebook|
		match msg {
			UserClickedRemove =>
				(model, notebook.remove(model.id), [Navigation.replace_url(Route.to_path(Notes))])
		}

	view : Note, Notebook -> Html(Msg)
	view = |model, notebook|
		match notebook.text_of(model.id) {
			Ok(note) =>
				div(
					[],
					[
						h1([], [text("Note ${model.id.to_str()}")]),
						p([], [text(note)]),
						p([], [button([on_click(UserClickedRemove)], [text("Remove")])]),
						back,
					],
				)

			Err(NoSuchNote) =>
				div([], [h1([], [text("No such note")]), p([], [text("There is no note ${model.id.to_str()}.")]), back])
		}
}

back : Html(Note.Msg)
back = p([], [a([href(Route.to_path(Notes))], [text("All notes")])])
