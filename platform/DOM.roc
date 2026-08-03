## Browser navigation and native dialogs. These are one-way effects with no
## response: return them from `init` or `update` (e.g.
## `(model, [DOM.push_url("?q=1")])`) and the host performs them after
## the paint. Reacting to the user's Back/Forward buttons is a subscription.
##
## The three ways to change the URL:
##
##     DOM.replace_url  rewrite the URL in place, no reload, no history entry
##     DOM.push_url     change the URL, no reload, adds a history entry
##     DOM.navigate     a full page load (leaves the current page)
import Effect exposing [Effect]
import Sub exposing [Sub]

DOM := [].{

	## Open the `<dialog>` element matching this CSS selector as a modal
	## (the element's `showModal()`): centered, on the top layer, with
	## everything behind it inert. Render the dialog and its contents from
	## your model like any other element; only the open/closed state lives
	## outside the model, which is why it is driven by an effect rather than
	## an attribute. No-op when the selector matches nothing or the element
	## is not a dialog. Note the user can dismiss a modal with Escape, so pair
	## it with a "close" msg that also returns `close_modal` and your model never
	## disagrees with what is on screen for long.
	show_modal : Str -> Effect(msg)
	show_modal = |selector| Effect.show_modal(selector)

	## Close the `<dialog>` element matching this CSS selector (the
	## element's `close()`). No-op when it is not open.
	close_modal : Str -> Effect(msg)
	close_modal = |selector| Effect.close_modal(selector)

	## A full page load. The app re-initialises, so the model is lost.
	navigate : Str -> Effect(msg)
	navigate = |url| Effect.navigate(url)

	## Change the URL without reloading and add a history entry, so Back
	## returns to the previous URL. Pair with `on_url_change` so the view
	## reacts when the user steps back through those entries.
	push_url : Str -> Effect(msg)
	push_url = |url| Effect.push_url(url)

	## Rewrite the URL in place: no reload and no history entry. Built for
	## things like keeping "?q=..." in sync with a search box, where Back
	## should not step through every keystroke.
	replace_url : Str -> Effect(msg)
	replace_url = |url| Effect.replace_url(url)

	## Fire a message when the browser's back/forward buttons change the URL
	## (the `popstate` event), with the new path (path + query + fragment).
	## Programmatic changes (`push_url`, `replace_url`) do not fire it
	## because the app already knows about those.
	on_url_change : (Str -> msg) -> Sub(msg)
	on_url_change = |on_change| Sub.url_changed(on_change)
}
