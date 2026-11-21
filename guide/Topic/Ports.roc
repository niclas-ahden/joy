import html.Html exposing [a, code, h1, h2, p, text]
import html.Attribute exposing [class, href]
import /Doc
import "../samples/ports.roc" as ports : Str
import "../pages/ports.html" as ports_page : Str

## The topic "Ports".
Ports := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("JavaScript interop")]),
		h1([], [text("Ports")]),
		p(
			[class("lead")],
			[
				text("A port is a named line between your app and the JavaScript on its page. Text goes out on one, and text comes in on another."),
			],
		),
		p(
			[],
			[
				text("Use a port when your page already has some JavaScript that your app should talk to: a chart, a map, a widget someone else wrote."),
			],
		),
		h2([], [text("In your app")]),
		p(
			[],
			[
				text("Sending is an effect, and listening is a subscription. "),
				Doc.api("Port.send(\"cheer\", \"Hello!\")"),
				text(" sends a text on the port called "),
				c("cheer"),
				text(". "),
				Doc.api("Port.listen(\"tick\", |text| JavaScriptTicked)"),
				text(" turns every text that arrives on "),
				c("tick"),
				text(" into a message."),
			],
		),
		h2([], [text("On your page")]),
		p(
			[],
			[
				c("joy.js"),
				text(" tells the page about your app twice. "),
				c("joy:mount"),
				text(" comes before the app starts, and is where you say what to do with what the app sends, with "),
				c("app.onPort"),
				text(". "),
				c("joy:mounted"),
				text(" comes once it runs, and hands you the app to send to, with "),
				c("app.sendPort"),
				text("."),
			],
		),
		h2([], [text("Try it")]),
		p(
			[],
			[
				text("The page sends a tick every second, and the Cheer button sends a line back. Open "),
				c("index.html"),
				text(" in the top-left and make it tick faster 👇"),
			],
		),
		Doc.with_page("ports.roc", shown(ports), ports_page),
		p(
			[],
			[
				text("A port carries text. To send more than that, send JSON and parse it on the other side. And when you want a browser feature as a function of its own in Roc, with types, write a "),
				a([href("#custom-effects")], [text("custom effect")]),
				text("."),
			],
		),
	]
}

c : Str -> Html([])
c = |source| code([], [text(source)])

## The sample as the guide shows it: on a release of Joy, as a project of
## your own would be.
shown : Str -> Str
shown = |source| source.replace_first("pf: platform \"../../platform/main.roc\"", Doc.platform_line)
