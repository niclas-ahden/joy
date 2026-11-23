import html.Html exposing [a, code, em, h1, h2, li, p, text, ul]
import html.Attribute exposing [class, href, rel, target]
import /Doc

## The topic "Views".
Views := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Views")]),
		p([class("lead")], [text("OK, now let's build a view with a bit more in it: a guest list!")]),
		p(
			[],
			[
				text("An HTML element is a function that takes a list of attributes and a list of children. So far the only attribute we have used is "),
				code([], [text("on_click")]),
				text(". This app uses a few more."),
			],
		),
		Doc.editor_folded(
			Doc.code(
				Roc,
				"guests.roc",
				\\app [Model, Msg, init, subscriptions, update, view] {
				\\    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\}
				\\
				\\import html.Html exposing [button, div, input, li, p, text, ul]
				\\import html.Attribute exposing [disabled, on_click, on_input, placeholder, value]
				\\import pf.Effect
				\\
				\\Model : { new_guest : Str, guests : List(Str) }
				\\
				\\Msg : [
				\\    UserTypedNewGuest(Str),
				\\    UserClickedInvite,
				\\    UserClickedRemove(Str),
				\\]
				\\
				\\init : Str -> (Model, List(Effect(Msg)))
				\\init = |_flags| ({ new_guest: "", guests: ["Ada", "Grace"] }, [])
				\\
				\\update : Model, Msg -> (Model, List(Effect(Msg)))
				\\update = |model, msg|
				\\    match msg {
				\\        UserTypedNewGuest(typed) =>
				\\            ({ ..model, new_guest: typed }, [])
				\\
				\\        UserClickedInvite =>
				\\            ({ new_guest: "", guests: List.append(model.guests, model.new_guest) }, [])
				\\
				\\        UserClickedRemove(guest) =>
				\\            ({ ..model, guests: List.drop_if(model.guests, |g| g == guest) }, [])
				\\    }
				\\
				\\view : Model -> Html(Msg)
				\\view = |model|
				\\    div(
				\\        [],
				\\        [
				\\            input([
				\\                placeholder("Who's coming?"),
				\\                value(model.new_guest),
				\\                on_input(|typed| UserTypedNewGuest(typed)),
				\\            ]),
				\\            button(
				\\                [on_click(UserClickedInvite), disabled(model.new_guest == "")],
				\\                [text("Invite")],
				\\            ),
				\\            ul([], List.map(model.guests, guest_row)),
				\\            p([], [text("\${model.guests.len().to_str()} coming")]),
				\\        ],
				\\    )
				\\
				\\guest_row : Str -> Html(Msg)
				\\guest_row = |guest|
				\\    li(
				\\        [],
				\\        [
				\\            text(guest),
				\\            button([on_click(UserClickedRemove(guest))], [text("Remove")]),
				\\        ],
				\\    )
				\\
				\\subscriptions = |_model| []
			),
		),
		p(
			[],
			[
				text("Most attributes take strings, like "),
				code([], [text("placeholder")]),
				text(" and "),
				code([], [text("value")]),
				text(". Others take booleans, like "),
				code([], [text("disabled")]),
				text(", and we set those like so: "),
				code([], [text("disabled(model.new_guest == \"\")")]),
				text(". This means we'll produce valid HTML and Roc's type-system will assist you :) You can of course still use "),
				a([href("https://niclas-ahden.github.io/joy-html/main/Html/#Html.element"), target("_blank"), rel("noopener")], [text("custom elements")]),
				text(" and "),
				a([href("https://niclas-ahden.github.io/joy-html/main/Attribute/#Attribute.attribute"), target("_blank"), rel("noopener")], [text("attributes")]),
				text(" when you need to."),
			],
		),
		p(
			[],
			[
				text("Try adding an attribute yourself, like "),
				code([], [text("title(\"Add them to the list\")")]),
				text(" on the Invite button. Start typing and the editor suggests elements and attributes, and adds the one you pick to the "),
				code([], [text("import")]),
				text(" line."),
			],
		),
		p(
			[],
			[
				text("All elements and attributes are defined in "),
				a([href("https://niclas-ahden.github.io/joy-html/"), target("_blank"), rel("noopener")], [code([], [text("joy-html")])]),
				text(". Since it's a separate package we can also use it on the back-end, and that's how we share HTML throughout the stack!"),
			],
		),
		h2([], [text("Events are attributes too")]),
		p(
			[],
			[
				text("Events are attributes that carry a message. "),
				code([], [text("on_click(UserClickedInvite)")]),
				text(" sends a message as it is. An input sends what was typed, so "),
				code([], [text("on_input")]),
				text(" takes a function from the typed text to a message: "),
				code([], [text("on_input(|typed| UserTypedNewGuest(typed))")]),
				text("."),
			],
		),
		p([], [text("Type \"you\" in the box below and watch the messages come in 👇")]),
		Doc.editor_folded(
			Doc.code(
				Roc,
				"typing.roc",
				\\app [Model, Msg, init, subscriptions, update, view] {
				\\    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\}
				\\
				\\import html.Html exposing [div, input, li, text, ul]
				\\import html.Attribute exposing [on_input, placeholder]
				\\import pf.Effect
				\\
				\\Model : { messages : List(Msg) }
				\\
				\\Msg : [UserTypedNewGuest(Str)]
				\\
				\\init : Str -> (Model, List(Effect(Msg)))
				\\init = |_flags| ({ messages: [] }, [])
				\\
				\\update : Model, Msg -> (Model, List(Effect(Msg)))
				\\update = |model, msg|
				\\    ({ messages: List.append(model.messages, msg) }, [])
				\\
				\\view : Model -> Html(Msg)
				\\view = |model|
				\\    div(
				\\        [],
				\\        [
				\\            input([
				\\                placeholder("Type here"),
				\\                on_input(|typed| UserTypedNewGuest(typed)),
				\\            ]),
				\\            ul([], List.map(model.messages, message_row)),
				\\        ],
				\\    )
				\\
				\\message_row : Msg -> Html(Msg)
				\\message_row = |msg| li([], [text(Str.inspect(msg))])
				\\
				\\subscriptions = |_model| []
			),
		),
		p(
			[],
			[
				text("You get three messages: "),
				code([], [text("UserTypedNewGuest(\"y\")")]),
				text(", "),
				code([], [text("UserTypedNewGuest(\"yo\")")]),
				text(" and "),
				code([], [text("UserTypedNewGuest(\"you\")")]),
				text(". Every key press sends a new message, and each one carries the whole text of the input, not just the last letter."),
			],
		),
		h2([], [text("The type tells you what a view can do")]),
		p(
			[],
			[
				text("The type of a view ends with "),
				code([], [text("Html(...)")]),
				text(", and inside the parentheses is the type of the messages it can send. The guest list's "),
				code([], [text("view")]),
				text(" returns "),
				code([], [text("Html(Msg)")]),
				text(", because its input and buttons send the messages of "),
				code([], [text("Msg")]),
				text("."),
			],
		),
		p([], [text("Now look at this one, which shows how many guests are coming:")]),
		Doc.code(
			Roc,
			"",
			\\guest_count : List(Str) -> Html(msg)
			\\guest_count = |guests| p([], [text("\${guests.len().to_str()} coming")])
		),
		p(
			[],
			[
				text("It returns "),
				code([], [text("Html(msg)")]),
				text(" with a lowercase "),
				code([], [text("msg")]),
				text(". In Roc, a lowercase name in a type is a "),
				em([], [text("type variable")]),
				text(": a blank that stands for any type. So "),
				code([], [text("guest_count")]),
				text(" doesn't pick a message type. Whoever uses it does. That tells you two things:"),
			],
		),
		ul(
			[],
			[
				li(
					[],
					[
						text("It works anywhere. Inside the guest list the blank is filled in with the guest list's "),
						code([], [text("Msg")]),
						text(". On another page it's filled in with that page's messages."),
					],
				),
				li(
					[],
					[
						text("It sends no messages of its own. It doesn't know which messages there are, so there's nothing it could put in an "),
						code([], [text("on_click")]),
						text("."),
					],
				),
			],
		),
		p(
			[],
			[
				text("Use the lowercase form whenever a view has no events. The type alone then tells the reader that this piece only shows things."),
			],
		),
		h2([], [text("Html.map")]),
		p(
			[],
			[
				text("When a part of the page has its own message type, "),
				Doc.api("Html.map"),
				text(" wraps every message it sends into a message of the page:"),
			],
		),
		Doc.code(
			Roc,
			"",
			\\Html.map(Counter.view(model.counter), |m| Counter(m))
		),
		p(
			[],
			[
				text("You will see this whenever an app is split into pages, and when a piece of UI has its own state."),
			],
		),
	]
}
