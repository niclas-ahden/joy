app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, button, input, text]
import html.Attribute exposing [id, type, on_click, on_file]
import pf.Effect
import pf.Media
import pf.Time

# What tests/check_many_apps.mjs and tests/e2e/many_apps_test.roc mount more than
# once on a page: every copy uses the same debounce key and gets the same file ids.

Model : { fired : I64, file : U32, url : Str }

Msg : [Arm, Cancel, Fired, Picked(U32), Ask, Got(Str)]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ fired: 0, file: 0, url: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Arm => (model, [Time.debounce("search", 80, |_| Fired)])
		Cancel => (model, [Time.cancel("search")])
		Fired => ({ ..model, fired: model.fired + 1 }, [])
		Picked(file) => ({ ..model, file }, [])
		Ask => (model, [Media.object_url(model.file, |answer| Got(answer ?? "failed"))])
		Got(url) => ({ ..model, url }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("arm"), on_click(Arm)], [text("Arm")]),
			button([id("cancel"), on_click(Cancel)], [text("Cancel")]),
			p([id("fired")], [text(model.fired.to_str())]),
			input([id("upload"), type("file"), on_file(|f| Picked(f.id))]),
			button([id("ask"), on_click(Ask)], [text("Ask")]),
			p([id("url")], [text(model.url)]),
		],
	)
