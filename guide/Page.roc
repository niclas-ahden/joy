import html.Html exposing [a, nav, section, span, text]
import html.Attribute exposing [aria, class, href, id]
import /Doc
import /Guide
import /Index
import /Topics

## The guide's page as it is published: page.html with the index and every
## topic rendered into it, where it says `<!-- index -->` and
## `<!-- topics -->`.
Page := [].{
	fill : Str -> Try(Str, [NoMarker(Str)])
	fill = |template| {
		with_index = put(template, "<!-- index -->", Str.join_with(Index.view.map(Html.render), "\n"))?
		put(with_index, "<!-- topics -->", Str.join_with(Topics.all.map(|topic| Html.render(topic_section(topic))), "\n"))
	}
}

## A topic with links to the ones before and after it.
topic_section : Topics.Topic -> Html([])
topic_section = |topic| {
	before = Topics.neighbour(topic, Before).map_ok(|t| pager_link(topic, t, "Previous", "prev")) ?? text("")
	after = Topics.neighbour(topic, After).map_ok(|t| pager_link(topic, t, "Next", "next")) ?? text("")
	pager = nav([class("pager"), aria("label", "Previous and next topic")], [before, after])
	body : Doc.Body
	body = Guide.body(topic)
	section([class("topic"), id(Topics.info(topic).id)], body.append(pager))
}

## A link from one topic to a neighbour. One in another part of the guide
## names that part too, as in "Examples: Hello".
pager_link : Topics.Topic, Topics.Topic, Str, Str -> Html([])
pager_link = |from, topic, direction, cls| {
	to = Topics.info(topic)
	name = if (to.part == Topics.info(from).part) to.title else "${to.part}: ${to.title}"
	a(
		[href("#${to.id}"), class(cls)],
		[span([class("dir")], [text(direction)]), span([class("name")], [text(name)])],
	)
}

put : Str, Str, Str -> Try(Str, [NoMarker(Str)])
put = |page, marker, html|
	match page.split_first(marker) {
		Ok({ before, after }) => Ok("${before}${html}${after}")
		Err(NotFound) => Err(NoMarker(marker))
	}
