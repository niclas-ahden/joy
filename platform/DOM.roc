## Browser navigation, focus, native dialogs, the page title and scrolling.
## These are one-way effects with no response: return them from `init` or
## `update` (e.g. `(model, [DOM.push_url("?q=1")])`) and the host performs
## them after the paint. Reacting to the user's Back/Forward buttons, and to
## clicks anywhere on the page, are subscriptions.
##
## The effects addressed by a CSS selector (`focus`, `show_modal`,
## `close_modal`) do nothing when the selector matches no element. That is
## deliberate, so an app can focus a field only some pages have, and there
## is no error to handle. The runtime does log a console warning naming the
## effect and the selector, which is how a typo shows up in development.
##
## The three ways to change the URL:
##
##     DOM.replace_url  rewrite the URL in place, no reload, no history entry
##     DOM.push_url     change the URL, no reload, adds a history entry
##     DOM.navigate     a full page load (leaves the current page)
import Effect
import Sub
import Wire

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
	show_modal = |selector| Effect.send("joy/dom/show_modal", Wire.writer({}).str(selector).done())

	## Close the `<dialog>` element matching this CSS selector (the
	## element's `close()`). No-op when it is not open.
	close_modal : Str -> Effect(msg)
	close_modal = |selector| Effect.send("joy/dom/close_modal", Wire.writer({}).str(selector).done())

	## Give keyboard focus to the element matching this CSS selector (the
	## element's `focus()`). Runs after the paint, so the selector can name
	## an element the same update just rendered or revealed: return
	## `(model_with_editing, [DOM.focus(".edit")])` and the field is open and
	## focused before the user's next keystroke. A text field gets its caret
	## at the end, so typing continues the value. No-op when the selector
	## matches nothing or the element cannot take focus (hidden, disabled).
	focus : Str -> Effect(msg)
	focus = |selector| Effect.send("joy/dom/focus", Wire.writer({}).str(selector).done())

	## Set the page's title, the text in the browser's tab and history
	## (`document.title`). Return it from the `init` and the `update`s that
	## change what the page shows, the way an app that switches pages in
	## place names each page.
	set_title : Str -> Effect(msg)
	set_title = |title| Effect.send("joy/dom/set_title", Wire.writer({}).str(title).done())

	## Scroll the page to a position in CSS pixels from its top left corner
	## (`window.scrollTo`), `{ x: 0, y: 0 }` for the top. Runs after the
	## paint, so a page the same update switched to starts at the top
	## instead of where the previous one was scrolled to.
	scroll_to : { x : U64, y : U64 } -> Effect(msg)
	scroll_to = |{ x, y }| Effect.send("joy/dom/scroll_to", Wire.writer({}).u64(x).u64(y).done())

	## A full page load. The app re-initialises, so the model is lost.
	navigate : Str -> Effect(msg)
	navigate = |url| Effect.send("joy/dom/navigate", Wire.writer({}).str(url).done())

	## Change the URL without reloading and add a history entry, so Back
	## returns to the previous URL. Pair with `on_url_change` so the view
	## reacts when the user steps back through those entries.
	push_url : Str -> Effect(msg)
	push_url = |url| Effect.send("joy/dom/push_url", Wire.writer({}).str(url).done())

	## Rewrite the URL in place: no reload and no history entry. Built for
	## things like keeping "?q=..." in sync with a search box, where Back
	## should not step through every keystroke.
	replace_url : Str -> Effect(msg)
	replace_url = |url| Effect.send("joy/dom/replace_url", Wire.writer({}).str(url).done())

	## Fire a message when the browser's back/forward buttons change the URL
	## (the `popstate` event), with the new path (path + query + fragment).
	## Programmatic changes (`push_url`, `replace_url`) do not fire it
	## because the app already knows about those.
	on_url_change : (Str -> msg) -> Sub(msg)
	on_url_change = |on_change|
		Sub.listen("joy/dom/url_changed", [], |event| on_change(Wire.reader(event).str().map_ok(|(url, _)| url) ?? ""))

	## Fire a message when the user clicks an element carrying this
	## attribute, or anything inside one, with the attribute's value. The
	## listener is on the document, so it also hears the page's own HTML
	## around the app's root, which the app does not render and so cannot
	## give handlers: `DOM.on_document_click("data-copy", |id| UserClickedCopy(id))`.
	## The nearest element with the attribute wins.
	on_document_click : Str, (Str -> msg) -> Sub(msg)
	on_document_click = |attribute, on_click|
		Sub.listen("joy/dom/document_clicks", Wire.writer({}).str(attribute).done(), |event| on_click(Wire.reader(event).str().map_ok(|(value, _)| value) ?? ""))
}

# Each helper is one operation. Pin its id and argument so a helper can
# never quietly produce its sibling (push as replace, show as close).

sent : Effect(msg) -> Try((Str, Str), [NotSent])
sent = |effect|
	match effect {
		Send(id, args) => Wire.reader(args).str().map_ok(|(value, _)| (id, value)).map_err(|_| NotSent)
		_ => Err(NotSent)
	}

expect sent(DOM.show_modal("#confirm")) == Ok(("joy/dom/show_modal", "#confirm"))
expect sent(DOM.close_modal("#confirm")) == Ok(("joy/dom/close_modal", "#confirm"))
expect sent(DOM.focus("#name")) == Ok(("joy/dom/focus", "#name"))
expect sent(DOM.navigate("/login")) == Ok(("joy/dom/navigate", "/login"))
expect sent(DOM.push_url("?page=2")) == Ok(("joy/dom/push_url", "?page=2"))
expect sent(DOM.replace_url("?q=hats")) == Ok(("joy/dom/replace_url", "?q=hats"))
expect sent(DOM.set_title("Inbox")) == Ok(("joy/dom/set_title", "Inbox"))

# x before y, so a scroll down never lands sideways.
expect {
	match DOM.scroll_to({ x: 3, y: 40 }) {
		Send(id, args) => id == "joy/dom/scroll_to" and args == Wire.writer({}).u64(3).u64(40).done()
		_ => Bool.False
	}
}

expect {
	sub = DOM.on_url_change(|url| "nav:${url}")
	sub.identity().id == "joy/dom/url_changed" and sub.deliver(Wire.writer({}).str("/diary?q=1").done()) == "nav:/diary?q=1"
}

# The attribute is the subscription's identity, so two attributes are two
# listeners.
expect {
	sub = DOM.on_document_click("data-copy", |value| "copy:${value}")
	identity = sub.identity()
	identity.id == "joy/dom/document_clicks" and identity.args == Wire.writer({}).str("data-copy").done() and sub.deliver(Wire.writer({}).str("code-1f").done()) == "copy:code-1f"
}
