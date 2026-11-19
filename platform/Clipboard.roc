## Copy text to the clipboard.
##
## ```roc
## Msg : [UserClickedCopy, Copied(Try({}, Clipboard.Problem))]
##
## copy : Str -> Effect(Msg)
## copy = |text| Clipboard.write_text(text, |r| Copied(r))
##
## update = |model, msg|
##     match msg {
##         UserClickedCopy => (model, [copy(model.link)])
##         Copied(Ok({})) => ({ ..model, note: "Copied!" }, [])
##         Copied(Err(_)) => ({ ..model, note: "Failed" }, [])
##     }
## ```
##
## ## When the browser says no
##
## A browser lets a page write to the clipboard only when both of these hold:
##
## - The page is served over HTTPS, or from localhost.
## - The write follows a click or a key press. So return the effect from the
##   `update` for that click's message, not later.
##
## Anything else comes back as an `Err` with a [Clipboard.Problem].
import Effect
import Wire

Clipboard := [].{

	## Why the text was not copied.
	##
	## - `NotAllowed`: the browser refused. Most often no click or key press led
	##   to the write, or the page did not have focus.
	## - `Insecure`: the page is not served over HTTPS (or from localhost).
	## - `Unsupported`: the browser has no clipboard to write to.
	## - `NotFound`: [Clipboard.write_text_of] was given a selector that matches
	##   nothing.
	## - `Other(name)`: anything else, with the browser's name for the error.
	Problem : [NotAllowed, Insecure, Unsupported, NotFound, Other(Str)]

	## Put a text on the clipboard. Your message says whether it worked, so a
	## Copy button can say "Copied", or ask the user to copy by hand.
	##
	## ```roc
	## Clipboard.write_text("roc build", |r| Copied(r))
	## ```
	write_text : Str, (Try({}, Clipboard.Problem) -> msg) -> Effect(msg)
	write_text = |text, on_done| Effect.call("joy/clipboard/write_text", Wire.writer({}).str(text).done(), |reply| on_done(done(reply)))

	## Put the text of an element on the clipboard: the element a CSS selector
	## matches. This is for text your app does not hold, like a code block in the
	## page around your app.
	##
	## ```roc
	## Clipboard.write_text_of("#install-command", |r| Copied(r))
	## ```
	##
	## The selector looks in your app's own view first, and then in the rest of
	## the page.
	write_text_of : Str, (Try({}, Clipboard.Problem) -> msg) -> Effect(msg)
	write_text_of = |selector, on_done| Effect.call("joy/clipboard/write_text_of", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))
}

done : List(U8) -> Try({}, Clipboard.Problem)
done = |reply| Effect.reply(reply).map_ok(|_| {}).map_err(problem)

## A failed reply has the browser's error name, the way the clipboard's
## JavaScript reports it: NotAllowedError when the document is not focused.
problem : [EffectFailed({ name : Str, message : Str })] -> Clipboard.Problem
problem = |EffectFailed({ name, .. })|
	match name {
		"NotAllowedError" => NotAllowed
		"SecurityError" => Insecure
		"NotSupportedError" => Unsupported
		"NotFoundError" => NotFound
		other => Other(other)
	}

expect done([0]) == Ok({})
expect done([1].concat(Str.to_utf8("NotAllowedError: Document is not focused."))) == Err(NotAllowed)
expect done([1].concat(Str.to_utf8("SecurityError: the clipboard needs HTTPS"))) == Err(Insecure)
expect done([1].concat(Str.to_utf8("NotSupportedError: no clipboard"))) == Err(Unsupported)
expect done([1].concat(Str.to_utf8("NotFoundError: nothing matches"))) == Err(NotFound)
expect done([1].concat(Str.to_utf8("TypeError: odd"))) == Err(Other("TypeError"))

expect Clipboard.write_text("roc build", |result| result).identity() == { id: "joy/clipboard/write_text", args: Wire.writer({}).str("roc build").done() }

expect Clipboard.write_text_of("#code-1f", |result| result).identity() == { id: "joy/clipboard/write_text_of", args: Wire.writer({}).str("#code-1f").done() }
