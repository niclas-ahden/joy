app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, button, input, text]
import html.Attribute exposing [id, on_click, on_input]
import pf.Effect
import pf.Http
import pf.Time
import pf.WebCrypto

# hot_fx_v1.roc with requests that build does not ask for (see
# tests/check_hot_effects.mjs): Bump now also reports to /analytics, and init
# loads /config. The Pick buttons swap places, so the one at the recorded
# position sends the other message, which only its text past the start tells
# apart. Greetings change their requests' headers (see `greeting`).

Model : {
	bumps : I64,
	saving : Bool,
	saved : Str,
	loaded : Str,
	reminded : I64,
	searched : I64,
	digest : Str,
	picked : Str,
	labeled : I64,
	config : Str,
	greeted : Str,
}

Response : Try(Http.Response, [HttpErr([Timeout, NetworkError])])

Msg : [
	Bump,
	Tracked(Response),
	Save,
	Saved(Response),
	Load,
	Loaded(Response),
	Remind,
	Reminded(I64),
	Search(Str),
	StopSearch,
	Searched(I64),
	Hash,
	Hashed(List(U8)),
	Pick(Str),
	Label(Str, I64 -> I64),
	Configured(Response),
	Greet(Str),
	Greeted(Str, Response),
]

# Longer than the 160 bytes of text a recorded message keeps for showing.
long : Str
long = Str.repeat("x", 200)

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (
	{ bumps: 0, saving: Bool.False, saved: "", loaded: "", reminded: 0, searched: 0, digest: "", picked: "", labeled: 0, config: "", greeted: "" },
	[Http.get("/config", |result| Configured(result))],
)

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Bump => ({ ..model, bumps: model.bumps + 1 }, [Http.post("/analytics", [], |result| Tracked(result))])
		Tracked(_) => (model, [])
		Save => ({ ..model, saving: Bool.True }, [Http.post("/save", Str.to_utf8("draft"), |result| Saved(result))])
		Saved(Ok(resp)) => ({ ..model, saving: Bool.False, saved: Str.from_utf8_lossy(resp.body) }, [])
		Saved(Err(_)) => ({ ..model, saving: Bool.False, saved: "failed" }, [])
		Load => (model, [Http.get("/load", |result| Loaded(result))])
		Loaded(Ok(resp)) => ({ ..model, loaded: Str.concat(model.loaded, Str.from_utf8_lossy(resp.body.take_first(16))) }, [])
		Loaded(Err(_)) => ({ ..model, loaded: Str.concat(model.loaded, "!") }, [])
		Remind => (model, [Time.after(300, |now| Reminded(now))])
		Reminded(_) => ({ ..model, reminded: model.reminded + 1 }, [])
		Search(_) => (model, [Time.debounce("search", 300, |now| Searched(now))])
		StopSearch => (model, [Time.cancel("search")])
		Searched(_) => ({ ..model, searched: model.searched + 1 }, [])
		Hash => (model, [WebCrypto.digest(Sha256, Str.to_utf8("joy"), |bytes| Hashed(bytes))])
		Hashed(bytes) => ({ ..model, digest: WebCrypto.to_hex(bytes) }, [])
		Pick(name) => ({ ..model, picked: name.drop_prefix(long) }, [])
		Label(_, step) => ({ ..model, labeled: step(model.labeled) }, [])
		Configured(Ok(resp)) => ({ ..model, config: Str.from_utf8_lossy(resp.body) }, [])
		Configured(Err(_)) => ({ ..model, config: "failed" }, [])
		Greet(lang) => (model, greeting(lang))
		Greeted(lang, Ok(resp)) => ({ ..model, greeted: Str.concat(model.greeted, "${lang}: ${Str.from_utf8_lossy(resp.body)};") }, [])
		Greeted(lang, Err(_)) => ({ ..model, greeted: Str.concat(model.greeted, "${lang}: failed;") }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("bump"), on_click(Bump)], [text("Bump")]),
			button([id("save"), on_click(Save)], [text("Save")]),
			button([id("load"), on_click(Load)], [text("Load")]),
			button([id("remind"), on_click(Remind)], [text("Remind")]),
			input([id("search"), on_input(|term| Search(term))]),
			button([id("stop-search"), on_click(StopSearch)], [text("Stop")]),
			button([id("hash"), on_click(Hash)], [text("Hash")]),
			button([id("pick-b"), on_click(Pick(Str.concat(long, "B")))], [text("B")]),
			button([id("pick-a"), on_click(Pick(Str.concat(long, "A")))], [text("A")]),
			button([id("label"), on_click(Label(long, |n| n + 1))], [text("Label")]),
			p([id("bumps")], [text(model.bumps.to_str())]),
			p([id("saving")], [text(if model.saving "saving" else "idle")]),
			p([id("saved")], [text(model.saved)]),
			p([id("loaded")], [text(model.loaded)]),
			p([id("reminded")], [text(model.reminded.to_str())]),
			p([id("searched")], [text(model.searched.to_str())]),
			p([id("digest")], [text(model.digest)]),
			p([id("picked")], [text(model.picked)]),
			p([id("labeled")], [text(model.labeled.to_str())]),
			p([id("config")], [text(model.config)]),
			button([id("greet-en"), on_click(Greet("en"))], [text("en")]),
			button([id("greet-sv"), on_click(Greet("sv"))], [text("sv")]),
			button([id("greet-de"), on_click(Greet("de"))], [text("de")]),
			p([id("greeted")], [text(model.greeted)]),
		],
	)

# A greeting in `lang`, the same request to /greet but for its Accept-Language
# header. Unlike hot_fx_v1.roc, English no longer asks for one, and German
# asks for de-DE rather than de.
greeting : Str -> List(Effect(Msg))
greeting = |lang|
	if lang == "en" {
		[]
	} else if lang == "de" {
		[greet(lang, "de-DE")]
	} else {
		[greet(lang, lang)]
	}

greet : Str, Str -> Effect(Msg)
greet = |lang, accept|
	Http.request({ ..Http.default_request, uri: "/greet", headers: [{ name: "Accept-Language", value: accept }] }, |result| Greeted(lang, result))
