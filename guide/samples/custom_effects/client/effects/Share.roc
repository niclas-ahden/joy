import pf.Effect
import pf.Wire

## The browser's share sheet. Its JavaScript is Share.js beside this file.
Share := [].{

	## Why nothing was shared: the person closed the sheet, the browser has
	## none, or something else, in the browser's words.
	Problem : [Cancelled, Unavailable, Other(Str)]

	## Offer a link to the apps the person shares with.
	link : { title : Str, url : Str }, (Try({}, Problem) -> msg) -> Effect(msg)
	link = |{ title, url }, to_msg|
		Effect.call(
			"my_app/share_link",
			Wire.writer({}).str(title).str(url).done(),
			|reply| to_msg(outcome(reply)),
		)
}

## A failure has the name of the browser's error.
outcome : List(U8) -> Try({}, Share.Problem)
outcome = |reply|
	match Effect.reply(reply) {
		Ok(_) => Ok({})
		Err(EffectFailed({ name: "AbortError", .. })) => Err(Cancelled)
		Err(EffectFailed({ name: "NotSupportedError", .. })) => Err(Unavailable)
		Err(EffectFailed({ message, .. })) => Err(Other(message))
	}

expect outcome([0]) == Ok({})
expect outcome(Str.to_utf8("\u(01)AbortError: Share canceled")) == Err(Cancelled)
expect outcome(Str.to_utf8("\u(01)NotSupportedError: This browser has no share sheet")) == Err(Unavailable)
expect outcome(Str.to_utf8("\u(01)NotAllowedError: Not now")) == Err(Other("Not now"))
