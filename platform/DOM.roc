## Change the page's title, the focus and the scroll position, and open and
## close dialogs.
##
## Most of these are effects with nothing to answer. Return them from `init`
## or `update`, and they run once the view is up to date:
##
## ```roc
## UserClickedEdit =>
##     ({ ..model, editing: Bool.True }, [DOM.focus("#title")])
## ```
##
## ## Selectors
##
## [DOM.focus], [DOM.show_modal] and [DOM.close_modal] find their element by a
## CSS selector, like `"#title"`. The selector looks in your app's own view
## first, and then in the rest of the page.
##
## A selector that matches nothing does nothing, so you can focus a field that
## only some of your pages have. The browser's console gets a warning that
## names the effect and the selector, which is how a typo shows up while you
## work.
##
## The URL has a module of its own, `Navigation`.
##
## The guide has [a modal example](../../#example-modal) to try.
import Effect
import Sub
import Wire

DOM := [].{

	## Open a `<dialog>` element as a modal: on top of the page, with everything
	## behind it out of reach.
	##
	## ```roc
	## UserClickedDelete => (model, [DOM.show_modal("#confirm")])
	## ```
	##
	## Render the dialog and what is in it from your model, like any element.
	## Only whether it is open lives in the browser, which is why opening it is an
	## effect.
	##
	## The user can close a modal with Escape too. If your model keeps track of
	## whether it is open, listen for the dialog's `close` event:
	## `on("close", UserClosedDialog)`.
	show_modal : Str -> Effect(msg)
	show_modal = |selector| Effect.send("joy/dom/show_modal", Wire.writer({}).str(selector).done())

	## Close a `<dialog>` element. Does nothing when it is not open.
	##
	## ```roc
	## UserClickedKeep => (model, [DOM.close_modal("#confirm")])
	## ```
	close_modal : Str -> Effect(msg)
	close_modal = |selector| Effect.send("joy/dom/close_modal", Wire.writer({}).str(selector).done())

	## Give an element the keyboard focus.
	##
	## It runs after the view is up to date, so it can name an element the same
	## `update` just showed. The field is open and focused before the user's next
	## key press:
	##
	## ```roc
	## UserClickedEdit =>
	##     ({ ..model, editing: Bool.True }, [DOM.focus("#title")])
	## ```
	##
	## A text field gets its cursor at the end, so typing carries on from what is
	## there. Does nothing when the element cannot take focus, like a hidden or a
	## disabled one.
	focus : Str -> Effect(msg)
	focus = |selector| Effect.send("joy/dom/focus", Wire.writer({}).str(selector).done())

	## Set the page's title: the text in the browser's tab and in its history.
	##
	## ```roc
	## DOM.set_title("Inbox (3)")
	## ```
	##
	## An app with several pages returns it wherever it changes page.
	set_title : Str -> Effect(msg)
	set_title = |title| Effect.send("joy/dom/set_title", Wire.writer({}).str(title).done())

	## Scroll the page to a position, in pixels from its top left corner.
	##
	## ```roc
	## DOM.scroll_to({ x: 0, y: 0 })
	## ```
	##
	## It runs after the view is up to date, so a page you just switched to starts
	## at the top and not where the last one was scrolled to.
	scroll_to : { x : U64, y : U64 } -> Effect(msg)
	scroll_to = |{ x, y }| Effect.send("joy/dom/scroll_to", Wire.writer({}).u64(x).u64(y).done())

	## A message when the user clicks an element that has a given attribute, or
	## anything inside one. The message gets the attribute's value.
	##
	## ```roc
	## DOM.on_document_click("data-copy", |id| UserClickedCopy(id))
	## ```
	##
	## It listens on the whole page, so it also hears the page's own HTML around
	## your app, which your app does not render and cannot put handlers on. When
	## several elements around the click have the attribute, the nearest one
	## counts.
	on_document_click : Str, (Str -> msg) -> Sub(msg)
	on_document_click = |attribute, on_click|
		Sub.listen("joy/dom/document_clicks", Wire.writer({}).str(attribute).done(), |event| on_click(Wire.reader(event).str().map_ok(|(value, _)| value) ?? ""))
}

# Each helper is one effect. Pin its id and argument so a helper can
# never quietly produce its sibling (push as replace, show as close).

sent : Effect(msg) -> Try((Str, Str), [NotSent])
sent = |effect|
	match effect {
		Send(_, args) => Wire.reader(args).str().map_ok(|(value, _)| (effect.identity().id, value)).map_err(|_| NotSent)
		_ => Err(NotSent)
	}

expect sent(DOM.show_modal("#confirm")) == Ok(("joy/dom/show_modal", "#confirm"))
expect sent(DOM.close_modal("#confirm")) == Ok(("joy/dom/close_modal", "#confirm"))
expect sent(DOM.focus("#name")) == Ok(("joy/dom/focus", "#name"))
expect sent(DOM.set_title("Inbox")) == Ok(("joy/dom/set_title", "Inbox"))

# x before y, so a scroll down never lands sideways.
expect DOM.scroll_to({ x: 3, y: 40 }).identity() == { id: "joy/dom/scroll_to", args: Wire.writer({}).u64(3).u64(40).done() }

# The attribute is the subscription's identity, so two attributes are two
# listeners.
expect {
	sub = DOM.on_document_click("data-copy", |value| "copy:${value}")
	identity = sub.identity()
	identity.id == "joy/dom/document_clicks" and identity.args == Wire.writer({}).str("data-copy").done() and sub.deliver(Wire.writer({}).str("code-1f").done()) == "copy:code-1f"
}
