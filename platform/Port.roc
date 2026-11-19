## Send text between your app and the JavaScript on its page.
##
## A port has a name. Your app sends on a port with [Port.send] and listens
## to one with [Port.listen], and the page's JavaScript does the same from its
## side.
##
## ## From JavaScript to your app
##
## ```roc
## subscriptions = |_model| [
##     Port.listen("tick", |_text| JavaScriptTicked),
## ]
## ```
##
## ```js
## document.addEventListener('joy:mounted', (event) => {
##     event.detail.app.sendPort('tick', '');
## });
## ```
##
## ## From your app to JavaScript
##
## ```roc
## update = |model, msg|
##     match msg {
##         UserCheered => (model, [Port.send("cheer", "Hi!")])
##     }
## ```
##
## ```js
## document.addEventListener('joy:mount', (event) => {
##     event.detail.setup = (app) => {
##         app.onPort('cheer', (text) => console.log(text));
##     };
## });
## ```
##
## `joy.js`, the script that starts your app, sends both events. `joy:mount`
## comes before your app starts, so nothing it sends from `init` is missed.
## `joy:mounted` comes once it runs. If you call `mount` yourself, its `setup`
## option and the `app` it gives back are the same two.
##
## ## Good to know
##
## - A port carries text. To send more, send JSON: `Json.to_str` in Roc and
##   `JSON.parse` in JavaScript, or the other way round.
## - Sending on a name nobody listens to does nothing.
## - Two listeners on the same name both get the text.
## - Names belong to the whole app. In a component you mean to reuse, start
##   the name with the component's name.
##
## The guide has [a page on ports](../../#ports) with an example to try.
import Effect
import Sub
import Wire

Port := [].{

	## Listen to a port. Every text JavaScript sends on it becomes a message, for
	## as long as the subscription is in the list `subscriptions` returns.
	##
	## ```roc
	## Port.listen("price", |text| PriceChanged(text))
	## ```
	listen : Str, (Str -> msg) -> Sub(msg)
	listen = |name, decoder|
		Sub.listen("joy/port/listen", Wire.writer({}).str(name).done(), |event| decoder(Wire.reader(event).str().map_ok(|(value, _)| value) ?? ""))

	## Send a text on a port.
	##
	## ```roc
	## Port.send("level", "9")
	## ```
	send : Str, Str -> Effect(msg)
	send = |name, value| Effect.send("joy/port/send", Wire.writer({}).str(name).str(value).done())
}

expect {
	sub = Port.listen("prices", |s| "got:${s}")
	sub.identity() == { id: "joy/port/listen", args: Wire.writer({}).str("prices").done() } and sub.deliver(Wire.writer({}).str("42").done()) == "got:42"
}

expect Port.send("level", "9").identity() == { id: "joy/port/send", args: Wire.writer({}).str("level").str("9").done() }
