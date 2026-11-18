import pf.Effect
import pf.Wire

## The language and the time zone the browser is set to. Its JavaScript is
## Locale.js beside this file.
Locale := [].{
	Info : { language : Str, time_zone : Str }

	## Ask the browser.
	get : (Try(Info, Str) -> msg) -> Effect(msg)
	get = |to_msg| Effect.call("my_app/locale_get", [], |reply| to_msg(info(reply)))
}

## The answer: the language, then the time zone. What went wrong is said in
## words, for the page to show while the two halves are being written.
info : List(U8) -> Try(Locale.Info, Str)
info = |reply| {
	answer = Effect.reply(reply) ? |EffectFailed({ name, message })| "${name}: ${message}"
	(language, rest) = Wire.reader(answer).str() ? Wire.explain
	(time_zone, _) = rest.str() ? Wire.explain
	Ok({ language, time_zone })
}

expect info([0].concat(Wire.writer({}).str("sv-SE").str("Europe/Stockholm").done())) == Ok({ language: "sv-SE", time_zone: "Europe/Stockholm" })
expect info([0].concat(Wire.writer({}).str("sv-SE").done())) == Err("The bytes ended before everything was read: the JavaScript wrote fewer values than the Roc reads.")
expect info([0].concat(Wire.writer({}).str("sv-SE").bool(Bool.True).done())) == Err("Value 2 is a Bool, where the Roc reads a Str. The JavaScript and the Roc disagree on what is passed, or on its order.")
expect info(Str.to_utf8("\u(01)TypeError: no Intl")) == Err("TypeError: no Intl")
