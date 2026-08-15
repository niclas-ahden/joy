app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, button, article, h2, p, a, text, element]
import html.Attribute exposing [class, href, attribute, on_click]
import pf.Effect exposing [Effect]

# Benchmark app shaped like a listings search page: a header whose text
# changes on every message (typing, a slideshow tick) above a large card
# grid that does not change at all. tests/bench_render.mjs drives it and
# times how much each header-only message costs as the grid grows.
#
# Flags: {"n": 500, "lazy": false} set the number of cards and whether the
# grid is wrapped in Html.lazy, so both arms of the comparison come from
# one wasm.

Listing : { id : U64, title : Str, price : Str, city : Str, img : Str }

Model : {
	query : Str,
	tick : I64,
	use_lazy : Bool,
	listings : List(Listing),
}

Msg : [UserTyped, HeroTick]

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
	({ query: "", tick: 0, use_lazy, listings: make_listings(n) }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTyped => ({ ..model, query: "${model.query}x" }, [])
		HeroTick => ({ ..model, tick: model.tick + 1 }, [])
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

grid : List(Listing) -> Html(Msg)
grid = |listings|
	div([class("listings-list")], listings.map(card))

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			div(
				[class("search-header")],
				[
					button([on_click(UserTyped)], [text("type")]),
					button([on_click(HeroTick)], [text("tick")]),
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
