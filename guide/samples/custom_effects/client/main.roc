app [Model, Msg, init, subscriptions, update, view] {
	effects: "effects/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../../../platform/main.roc",
}

# The guide's custom effects in one app: the language and time zone the
# browser is set to, a share button on the browser's share sheet, and a line
# that says whether the browser is online. Their Roc and their JavaScript are
# in effects/, a package this app names.
import html.Html exposing [button, div, p, text]
import html.Attribute exposing [id, on_click]
import pf.Effect
import pf.Sub
import effects.Locale
import effects.Share
import effects.Network

Model : { locale : Str, network : Network.Status, note : Str }

Msg : [
	GotLocale(Try(Locale.Info, Str)),
	UserClickedShare,
	ShareEnded(Try({}, Share.Problem)),
	NetworkChanged(Network.Status),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ locale: "", network: Online, note: "" }, [Locale.get(|result| GotLocale(result))])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		GotLocale(Ok(info)) => ({ ..model, locale: "${info.language}, ${info.time_zone}" }, [])
		GotLocale(Err(why)) => ({ ..model, locale: why }, [])
		UserClickedShare =>
			(model, [Share.link({ title: "Joy", url: "https://github.com/niclas-ahden/joy" }, |result| ShareEnded(result))])

		ShareEnded(Ok({})) => ({ ..model, note: "Shared" }, [])
		ShareEnded(Err(Cancelled)) => ({ ..model, note: "Not shared" }, [])
		ShareEnded(Err(Unavailable)) => ({ ..model, note: "This browser has no share sheet" }, [])
		ShareEnded(Err(Other(message))) => ({ ..model, note: message }, [])
		NetworkChanged(network) => ({ ..model, network }, [])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [Network.on_change(|status| NetworkChanged(status))]

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			p([id("locale")], [text(model.locale)]),
			button([id("share"), on_click(UserClickedShare)], [text("Share")]),
			p([id("note")], [text(model.note)]),
			p(
				[id("network")],
				[
					text(
						match model.network {
							Online => "Online"
							Offline => "Offline"
						},
					),
				],
			),
		],
	)
