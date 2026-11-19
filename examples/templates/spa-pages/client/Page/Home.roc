import html.Html exposing [button, div, h1, p, text]
import html.Attribute exposing [aria, on_click]

## A page is just a view. The app passes in what to show (`count`), and
## which messages to send when the buttons are clicked.
Home := [].{
	view : { count : I64, on_decrement : msg, on_increment : msg } -> Html(msg)
	view = |{ count, on_decrement, on_increment }|
		div(
			[],
			[
				h1([], [text("Home")]),
				p([], [text("Edit client/Page/Home.roc and save. The page takes the change, and the count stays.")]),
				p(
					[],
					[
						button([on_click(on_decrement), aria("label", "One less")], [text("-")]),
						text(" ${count.to_str()} "),
						button([on_click(on_increment), aria("label", "One more")], [text("+")]),
					],
				),
			],
		)
}
