# Real-browser E2E: the navigation app (tests/apps) in Chromium, against the
# real History API the fake DOM only records calls to: replace_url rewrites
# the address bar without adding entries, push_url adds one, Back fires a
# real popstate that DOM.on_url_change turns into a message, and navigate is
# a genuine page load that boots the app afresh. The URL claims read the
# address bar the browser reports; evaluate! remains only for history.back(),
# which has no built-in.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

query = "#query"

main! = |_args| {
	{ browser, page } = Browser.open!("navigation", "#search")?

	# Typing replaces the URL in place, percent-encoded.
	page.find("#search").fill!("first")?
	page.find("#search").fill!("hats on")?
	assert!(page.url_contains("?q=hats%20on"))?

	# push_url changes the URL and keeps the model: the rendered query
	# survives the push.
	page.find("#push").click!()?
	assert!(page.url_contains("?demo=push"))?
	assert!(page.find(query).has_text("Current query: hats on"))?

	# Replace on top of the pushed entry, so Back has something visible to
	# return from...
	page.find("#search").fill!("second")?

	# ...then Back: a real popstate lands on the first entry (last replaced to
	# ?q=hats%20on) and DOM.on_url_change re-derives the query from it.
	_ = page.evaluate!("(history.back(), 'ok')")?
	assert!(page.find(query).has_text("Current query: hats on"))?
	assert!(page.url_contains("?q=hats%20on"))?

	# navigate is a full page load: the app re-initialises and the query is
	# gone (www/index.html passes empty flags).
	page.find("#reload").click!()?
	assert!(page.find(query).has_text("Current query:"))?
	assert!(page.url_contains("?reloaded=1"))?

	browser.close!()?
	Ok({})
}
