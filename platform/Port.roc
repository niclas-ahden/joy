## Ports connect your app to JavaScript in both directions with plain
## strings (encode structured data as JSON).
##
## Incoming (JS to Roc): JavaScript cannot build one of your Msg values, so
## you subscribe with a named decoder and JS sends strings to that name.
## Like every subscription, listening lasts exactly as long as the
## subscription stays in the list (see `Sub`), and two listeners on the same
## name both fire.
##
##     subscriptions = |_model| [Port.listen("excitement", |_| Tick)]
##
##     const app = await mount({ wasm: "./app.wasm", root, flags: "" })
##     app.sendPort("excitement", "")
##
## The decoder turns the string into one of your Msg values and `update`
## runs as usual.
##
## Outgoing (Roc to JS): return a `Port.send` effect and JS receives the
## value in the handler it registered for that name.
##
##     update = |model, msg| (model, [Port.send("level", "9")])
##
##     app.onPort("level", (value) => console.log(value))
##
## In both directions a name nobody registered is a no-op.
##
## Port names are global to the app. Pick one per port, and prefix it with
## the component name when writing reusable components, so two instances
## cannot claim each other's messages.
import Effect exposing [Effect]
import Sub exposing [Sub]

Port := [].{
	listen : Str, (Str -> msg) -> Sub(msg)
	listen = |name, decoder| Sub.port_listen(name, decoder)

	send : Str, Str -> Effect(msg)
	send = |name, value| Effect.port_send(name, value)
}
