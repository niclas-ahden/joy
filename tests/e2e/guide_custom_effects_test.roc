# Real-browser E2E: the app of the guide's Custom effects, the Roc and the
# JavaScript the topic shows, under ./joy dev. An effect answers with values,
# arguments reach the JavaScript, a failure arrives by its name, a subscription
# hears the browser, and saving the JavaScript starts the page over on it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
}

import pf.Env
import pf.Path
import playwright.Playwright
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	opt = Env.var_str!("JOY_OPT") ?? "speed"
	dir = "build/${opt}/guide_custom_effects"
	HotDev.fresh!(dir)?
	Path.utf8("${dir}/client/effects").create_all!()?
	Path.utf8("${dir}/public").create_all!()?
	# The sample sits as deep below the checkout as this copy, so its paths
	# to the platform hold.
	for file in ["main.roc", "effects/main.roc", "effects/Locale.roc", "effects/Locale.js", "effects/Share.roc", "effects/Share.js", "effects/Network.roc", "effects/Network.js"] {
		Path.utf8("${dir}/client/${file}").write_utf8!(Path.utf8("guide/samples/custom_effects/client/${file}").read_utf8!()?)?
	}
	Path.utf8("${dir}/public/index.html").write_utf8!("<div data-joy-bundle=\"main\"></div>\n<script type=\"module\" src=\"./joy.js\"></script>\n")?

	started = HotDev.run!(dir, "", "8780")?
	{ page, url, .. } = started
	HotDev.open!(page, "${url}/", "#share")?

	# An effect that answers: what this browser says of itself.
	zone = page.evaluate!("Intl.DateTimeFormat().resolvedOptions().timeZone")?
	language = page.evaluate!("navigator.language")?
	HotDev.shows!(page, "#locale", "${language}, ${zone}")?

	# Arguments reach the JavaScript in the order the Roc wrote them.
	_ = page.evaluate!(share_is("(data) => { window.shared = data.title + ' at ' + data.url; return Promise.resolve(); }"))?
	page.find("#share").click!()?
	HotDev.shows!(page, "#note", "Shared")?
	HotDev.same!(page.evaluate!("window.shared")?, "Joy at https://github.com/niclas-ahden/joy")?

	# A failure arrives with the name and the message of what was thrown.
	_ = page.evaluate!(share_is("() => Promise.reject(new DOMException('Share canceled', 'AbortError'))"))?
	page.find("#share").click!()?
	HotDev.shows!(page, "#note", "Not shared")?
	_ = page.evaluate!(share_is("() => Promise.reject(new DOMException('Not now', 'NotAllowedError'))"))?
	page.find("#share").click!()?
	HotDev.shows!(page, "#note", "Not now")?
	_ = page.evaluate!(share_is("undefined"))?
	page.find("#share").click!()?
	HotDev.shows!(page, "#note", "This browser has no share sheet")?

	# A subscription hears the browser's own events.
	_ = page.evaluate!(online_is("false", "offline"))?
	HotDev.shows!(page, "#network", "Offline")?
	_ = page.evaluate!(online_is("true", "online"))?
	HotDev.shows!(page, "#network", "Online")?

	# "Save Locale.js and the page starts over with the new JavaScript."
	HotDev.edit!("${dir}/client/effects/Locale.js", "str(navigator.language)", "str('tlh')")?
	HotDev.shows!(page, "#locale", "tlh, ${zone}")?

	HotDev.stop!(started)
}

## Put `value` where the page finds the browser's share sheet.
share_is : Str -> Str
share_is = |value| "(Object.defineProperty(navigator, 'share', { configurable: true, value: ${value} }), 'set')"

## Have the browser say it is online or not, and send its event.
online_is : Str, Str -> Str
online_is = |value, event| "(Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => ${value} }), dispatchEvent(new Event('${event}')), 'sent')"
