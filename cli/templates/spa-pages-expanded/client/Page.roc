import /Notebook
import /Page/About as AboutPage
import /Page/Note as NotePage
import /Page/Notes as NotesPage
import /Page/Quote as QuotePage
import /Route
import html.Html exposing [div, h1, p, text]
import pf.Effect
import pf.Sub

## The page you're on, along with that page's own state. Each tag is one
## page, and the pages themselves are the modules in Page/.
##
## `init`, `update`, `view` and `subscriptions` below are the same four
## functions an app has. Each one finds out which page you're on and calls
## that page's own function. app.roc calls these, so it never has to know
## about any single page.
##
## Notes and Note show and change the notebook, which belongs to the app.
## So `update` and `view` are handed the notebook and pass it on to them.
Page := [
	Notes(NotesPage),
	Note(NotePage),
	Quote(QuotePage),
	About,
	NotFound,
].{

	## Every page's messages, each under a tag that says whose they are.
	Msg : [
		NotesMsg(NotesPage.Msg),
		NoteMsg(NotePage.Msg),
		QuoteMsg(QuotePage.Msg),
	]

	## The route for the page you're on. We don't store the route in the
	## model. We work it out from the page, so the two can never disagree.
	route : Page -> Try(Route.Route, [NotFound])
	route = |page|
		match page {
			Notes(_) => Ok(Notes)
			Note(note) => Ok(Note(note.id))
			Quote(_) => Ok(Quote)
			About => Ok(About)
			NotFound => Err(NotFound)
		}

	## Start the page for a route. A page that needs data, like Quote, asks
	## for it in its own `init`, so it's fetched every time you visit it.
	init : Try(Route.Route, [NotFound]) -> (Page, List(Effect(Msg)))
	init = |to|
		match to {
			Ok(Notes) => (Notes(NotesPage.init), [])
			Ok(Note(id)) => (Note(NotePage.init(id)), [])
			Ok(Quote) => {
				(quote, effects) = QuotePage.init
				(Quote(quote), Effect.map_all(effects, |m| QuoteMsg(m)))
			}
			Ok(About) => (About, [])
			Err(NotFound) => (NotFound, [])
		}

	## Hand a message to the page it belongs to. If you're no longer on that
	## page we ignore it. That happens when e.g. an HTTP response arrives
	## after you've navigated away.
	update : Page, Msg, Notebook -> (Page, Notebook, List(Effect(Msg)))
	update = |page, msg, notebook|
		match msg {
			NotesMsg(page_msg) =>
				match page {
					Notes(notes) => {
						(next, changed, effects) = notes.update(page_msg, notebook)
						(Notes(next), changed, Effect.map_all(effects, |m| NotesMsg(m)))
					}
					_ => (page, notebook, [])
				}

			NoteMsg(page_msg) =>
				match page {
					Note(note) => {
						(next, changed, effects) = note.update(page_msg, notebook)
						(Note(next), changed, Effect.map_all(effects, |m| NoteMsg(m)))
					}
					_ => (page, notebook, [])
				}

			QuoteMsg(page_msg) =>
				match page {
					Quote(quote) => {
						(next, effects) = quote.update(page_msg)
						(Quote(next), notebook, Effect.map_all(effects, |m| QuoteMsg(m)))
					}
					_ => (page, notebook, [])
				}
		}

	view : Page, Notebook -> Html(Msg)
	view = |page, notebook|
		match page {
			Notes(notes) => notes.view(notebook).map(|m| NotesMsg(m))
			Note(note) => note.view(notebook).map(|m| NoteMsg(m))
			Quote(quote) => quote.view().map(|m| QuoteMsg(m))
			About => AboutPage.view({})
			NotFound => div([], [h1([], [text("Not found")]), p([], [text("There is no page here.")])])
		}

	subscriptions : Page -> List(Sub(Msg))
	subscriptions = |page|
		match page {
			Notes(notes) => Sub.map_all(notes.subscriptions(), |m| NotesMsg(m))
			Note(_) | Quote(_) | About | NotFound => []
		}
}
