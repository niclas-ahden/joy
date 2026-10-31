app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect
import pf.Http

# The first of two builds that tests/check_hot.mjs reloads between, whose
# messages carry what Str.inspect prints without its contents: a function and
# an opaque value. Every Apply reads `Apply(<function>)` and every Choose
# reads `Choose(<opaque>)`, so a replay has to tell their buttons apart some
# other way. hot_fn_v2.roc swaps the buttons of each pair, and the twins
# differ in nothing but the function they carry.

Flavor :: Str

Model : { count : I64, flavor : Str, quote : Str }

Msg : [Apply(I64 -> I64), Choose(Flavor), Fetch, Got(Try(Http.Response, [HttpErr([Timeout, NetworkError])]))]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 1, flavor: "", quote: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Apply(f) => ({ ..model, count: f(model.count) }, [])
		Choose(Flavor.(name)) => ({ ..model, flavor: name }, [])
		Fetch => (model, [Http.get("/quote", |result| Got(result))])
		Got(Ok(resp)) => ({ ..model, quote: Str.from_utf8_lossy(resp.body) }, [])
		Got(Err(_)) => ({ ..model, quote: "failed" }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("plus"), on_click(Apply(|n| n + 1))], [text("+1")]),
			button([id("times"), on_click(Apply(|n| n * 10))], [text("x10")]),
			button([id("vanilla"), on_click(Choose(Flavor.("vanilla")))], [text("Vanilla")]),
			button([id("mint"), on_click(Choose(Flavor.("mint")))], [text("Mint")]),
			div([id("twins")], [button([on_click(Apply(|n| n - 1))], [text("go")]), button([on_click(Apply(|n| n * 0))], [text("go")])]),
			p([id("count")], [text(model.count.to_str())]),
			p([id("flavor")], [text(model.flavor)]),
			button([id("fetch"), on_click(Fetch)], [text("Fetch")]),
			p([id("quote")], [text(model.quote)]),
		],
	)
