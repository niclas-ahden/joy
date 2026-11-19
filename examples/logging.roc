app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [button, div, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Console

# Two ways to reach the browser console:
#
#   Console.log  the app logging effect. Deliberate output your app owns:
#                you write the message, return the effect from `init` or
#                `update`, and it lands in `console.log`.
#   dbg          the development printf. Throwaway inspection while you
#                work: drop `dbg expr` as a statement anywhere in pure
#                code (the effect system treats it as pure), the compiler
#                renders the inspected value, and it lands in
#                `console.debug`, under the Verbose level in devtools.
#                Statement form only, `x = dbg y` is not supported.
#
# Reach for Console.log when the output is part of the app. Reach for dbg
# when you want a quick look at a value and will delete the line after.

Model : { clicks : I64 }

Msg : [UserClicked]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ clicks: 0 }, [Console.log("The app booted")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClicked => {
			next = { clicks: model.clicks + 1 }
			# Inspect the whole model on its way out, at debug level.
			dbg next
			# The message the app means to log, at log level.
			(next, [Console.log("Clicked ${next.clicks.to_str()} times")])
		}
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([on_click(UserClicked)], [text("Click me")]),
			text("Clicks: ${model.clicks.to_str()}"),
		],
	)

# No subs needed for this example!
subscriptions = |_model| []
