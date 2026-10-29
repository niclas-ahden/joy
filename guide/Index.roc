import html.Html exposing [a, button, div, h2, header, input, label, nav, p, span, text]
import html.Attribute exposing [aria, autocomplete, class, data, for_, hidden, href, id, placeholder, style, type]
import /Topics

## The guide's index and the phone's bar above it, as the page is built
## with them. The page's script filters the links by their `data-words`,
## marks the topic on screen and opens the index on a phone.
Index := [].{
	view : List(Html([]))
	view = [bar, index]
}

bar : Html([])
bar =
	header(
		[class("bar")],
		[
			brand_name,
			button([type("button"), aria("expanded", "false"), aria("controls", "index")], [text("Topics")]),
		],
	)

brand_name : Html([])
brand_name = p([class("brand-name")], [text("Joy guide")])

## The list of topics, by part.
index : Html([])
index = {
	parts = Topics.all.fold(
		[],
		|acc, topic| {
			name = Topics.info(topic).part
			if (acc.contains(name)) acc else acc.append(name)
		},
	)
	nav(
		[class("index"), id("index"), aria("label", "Topics")],
		[
			div([class("brand")], [brand_name, p([class("brand-sub")], [text("Building and structuring web apps in Roc")])]),
			p(
				[class("docs-links")],
				[
					a([href("./LATESTVERSION/")], [text("API docs "), span([], [text("for LATESTVERSION")])]),
				],
			),
			label([for_("filter"), class("eyebrow"), style([("margin", "0")])], [text("Find a topic")]),
			input([class("filter"), id("filter"), type("search"), placeholder("Effects, routes, components..."), autocomplete("off")]),
			div([class("toc")], parts.map(index_part)),
			p([class("toc-empty"), hidden(Bool.True)], [text("No topic matches. Try another word.")]),
		],
	)
}

index_part : Str -> Html([])
index_part = |part|
	div(
		[class("toc-part")],
		[h2([], [text(part)])].concat(Topics.all.keep_if(|topic| Topics.info(topic).part == part).map(index_link)),
	)

## A topic's link, with the words a search finds it by.
index_link : Topics.Topic -> Html([])
index_link = |topic| {
	info = Topics.info(topic)
	number = Topics.position(topic) + 1
	a(
		[href("#${info.id}"), data("words", "${info.title} ${info.keywords}".with_ascii_lowercased())],
		[span([class("n")], [text(if (number < 10) "0${number.to_str()}" else number.to_str())]), span([], [text(info.title)])],
	)
}
