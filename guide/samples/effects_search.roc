app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [input, text]
import html.Attribute exposing [on_input]
import pf.Effect
import pf.Http
import pf.Time

Model : { query : Str, found : Str }

Msg : [
	UserTypedQuery(Str),
	UserPausedTyping,
	ServerAnsweredSearch(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ query: "", found: "" }, [])

search_url : Str -> Str
search_url = |query| "/api/search?q=${query}"

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTypedQuery(query) =>
			({ ..model, query }, [Time.debounce("search", 200, |_| UserPausedTyping)])

		UserPausedTyping =>
			(model, [Http.get(search_url(model.query), |result| ServerAnsweredSearch(result))])

		ServerAnsweredSearch(Ok(response)) => ({ ..model, found: Str.from_utf8_lossy(response.body) }, [])
		ServerAnsweredSearch(Err(_)) => ({ ..model, found: "" }, [])
	}

view : Model -> Html(Msg)
view = |model|
	Html.div([], [input([on_input(|typed| UserTypedQuery(typed))]), text(model.found)])
