app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, button, article, h2, p, a, text, element]
import html.Attribute exposing [class, href, attribute, on_click]
import pf.Effect

# Benchmark app shaped like a listings search page: a header whose text
# changes on every message (typing, a slideshow tick) above a large card
# grid that does not change at all. tests/bench_render.mjs drives it and
# times how much each header-only message costs as the grid grows. Two
# messages change the header's shape instead: `Swap` turns its badge into
# another element, which the host sends as a REPLACE, and `Rotate` moves
# the items of two short keyed lists, two REORDERs in one paint.
#
# Flags: {"n": 500, "lazy": false} set the number of cards and whether the
# grid is wrapped in Html.lazy, so both arms of the comparison come from
# one wasm.

Listing : { id : U64, title : Str, price : Str, city : Str, img : Str }

Model : {
	query : Str,
	tick : I64,
	badge_em : Bool,
	order : List(U64),
	use_lazy : Bool,
	listings : List(Listing),
}

Msg : [UserTyped, HeroTick, Swap, Rotate]

# No recurring event sources.
subscriptions = |_model| []

make_listings : U64 -> List(Listing)
make_listings = |n|
	(1..=n).iter()
		.map(
			|id| {
				id,
				title: "Länsmansvägen ${id.to_str()}",
				price: "${(id * 950).to_str()} 000 kr",
				city: "Skellefteå",
				img: "/images/listings/${id.to_str()}/hero-1200w.avif",
			},
		)
		.collect()

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	decoded : Try({ n : U64, lazy : Bool }, _)
	decoded = Json.parse(flags)
	(n, use_lazy) =
		match decoded {
			Ok(parsed) => (parsed.n, parsed.lazy)
			Err(_) => (100, Bool.False)
		}
	({ query: "", tick: 0, badge_em: Bool.False, order: [1, 2, 3, 4], use_lazy, listings: make_listings(n) }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTyped => ({ ..model, query: "${model.query}x" }, [])
		HeroTick => ({ ..model, tick: model.tick + 1 }, [])
		Swap => ({ ..model, badge_em: !model.badge_em }, [])
		Rotate => ({ ..model, order: model.order.drop_first(1).concat(model.order.take_first(1)) }, [])
	}

card : Listing -> Html(Msg)
card = |listing|
	article(
		[class("listing-card")],
		[
			element(
				"img",
				[
					class("listing-card__image"),
					attribute("src", listing.img),
					attribute("srcset", "${listing.img} 1200w, ${listing.img} 800w, ${listing.img} 400w"),
					attribute("alt", listing.title),
				],
				[],
			),
			h2([class("listing-card__title")], [text(listing.title)]),
			p([class("listing-card__price")], [text(listing.price)]),
			p([class("listing-card__city")], [text(listing.city)]),
			a([class("listing-card__link"), href("/bostad/${listing.id.to_str()}")], [text("Visa bostad")]),
		],
	)

# A short keyed list, so reordering `order` moves its items.
chips : List(U64), Str -> Html(Msg)
chips = |order, prefix|
	div([class("chips")], order.map(|id| Html.keyed("${prefix}${id.to_str()}", Html.span([], [text("${prefix}${id.to_str()}")]))))

grid : List(Listing) -> Html(Msg)
grid = |listings|
	div([class("listings-list")], listings.map(card))

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			div(
				[class("search-header")],
				[
					button([on_click(UserTyped)], [text("type")]),
					button([on_click(HeroTick)], [text("tick")]),
					button([on_click(Swap)], [text("swap")]),
					button([on_click(Rotate)], [text("rotate")]),
					if model.badge_em element("em", [class("badge")], [text("new")]) else Html.span([class("badge")], [text("new")]),
					chips(model.order, "a"),
					chips(model.order, "b"),
					text("q ${model.query}"),
					text(" tick ${model.tick.to_str()}"),
				],
			),
			# Only the list is passed, not the model, whose query/tick fields
			# change on every message and would force the grid every time.
			if model.use_lazy {
				Html.lazy(grid, model.listings)
			} else {
				grid(model.listings)
			},
		],
	)
