app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import Lab
import html.Html
import pf.Console
import pf.Effect

# The client half of the hydration lab: the view lives in Lab.roc, which
# ssr.roc renders into the pages this app boots over (see ssr.roc).
Model : Lab.Model

Msg : Lab.Msg

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Lab.decode(flags) {
		Ok(model) => (model, [])
		Err(e) => (Lab.default, [Console.log("hydrate_lab: could not parse the flags: ${Str.inspect(e)}")])
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg| (Lab.update(model, msg), [])

render : Model -> Html(Msg)
render = |model| Lab.view(model)
