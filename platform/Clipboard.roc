## The system clipboard, as an effect. The browser only lets a secure page
## (HTTPS, or localhost) write to it, and most browsers also want the write
## to follow the user's click or key press, so return it from the `update`
## for that message.
import Effect
import Wire

Clipboard := [].{

	## Why the browser said no. `NotAllowed` is the browser refusing, most
	## often because no click or key press led to the write or the page
	## does not have focus. `Insecure` is a page that is not HTTPS (or
	## localhost), and `Unsupported` a browser without the clipboard API.
	## `NotFound` is `write_text_of` given a selector nothing matches.
	Problem : [NotAllowed, Insecure, Unsupported, NotFound, Other(Str)]

	## Put text on the clipboard (`navigator.clipboard.writeText`). The
	## message says whether it worked, so a "Copy" button can say "Copied",
	## or tell the user to copy by hand when it did not.
	write_text : Str, (Try({}, Clipboard.Problem) -> msg) -> Effect(msg)
	write_text = |text, on_done| Effect.call("joy/clipboard/write_text", Wire.writer({}).str(text).done(), |reply| on_done(done(reply)))

	## Put the text of the element matching this CSS selector on the
	## clipboard (its `textContent`). For text the app does not hold, such
	## as a code block in the page's own HTML around the app's root.
	write_text_of : Str, (Try({}, Clipboard.Problem) -> msg) -> Effect(msg)
	write_text_of = |selector, on_done| Effect.call("joy/clipboard/write_text_of", Wire.writer({}).str(selector).done(), |reply| on_done(done(reply)))
}

done : List(U8) -> Try({}, Clipboard.Problem)
done = |reply| Effect.reply(reply).map_ok(|_| {}).map_err(problem)

## A failed reply's reason starts with the browser's error name, the way the
## clipboard feature reports it: "NotAllowedError: Document is not focused."
problem : [FeatureFailed(Str)] -> Clipboard.Problem
problem = |FeatureFailed(reason)| {
	name = reason.split_first(":").map_ok(|parts| parts.before) ?? reason
	match name.trim() {
		"NotAllowedError" => NotAllowed
		"SecurityError" => Insecure
		"NotSupportedError" => Unsupported
		"NotFoundError" => NotFound
		other => Other(other)
	}
}

expect done([0]) == Ok({})
expect done([1].concat(Str.to_utf8("NotAllowedError: Document is not focused."))) == Err(NotAllowed)
expect done([1].concat(Str.to_utf8("SecurityError: the clipboard needs HTTPS"))) == Err(Insecure)
expect done([1].concat(Str.to_utf8("NotSupportedError: no clipboard"))) == Err(Unsupported)
expect done([1].concat(Str.to_utf8("NotFoundError: nothing matches"))) == Err(NotFound)
expect done([1].concat(Str.to_utf8("TypeError: odd"))) == Err(Other("TypeError"))

expect {
	match Clipboard.write_text("roc build", |result| result) {
		Call(id, args, _) => id == "joy/clipboard/write_text" and args == Wire.writer({}).str("roc build").done()
		_ => Bool.False
	}
}

expect {
	match Clipboard.write_text_of("#code-1f", |result| result) {
		Call(id, args, _) => id == "joy/clipboard/write_text_of" and args == Wire.writer({}).str("#code-1f").done()
		_ => Bool.False
	}
}
