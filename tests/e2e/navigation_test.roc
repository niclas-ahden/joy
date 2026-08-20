# Real-browser E2E: the navigation app (tests/apps) in Chromium, against the
# real History API the fake DOM only records calls to: replace_url rewrites
# the address bar without adding entries, push_url adds one, Back fires a
# real popstate that DOM.on_url_change turns into a message, and navigate is
# a genuine page load that boots the app afresh. evaluate! is the access to
# location.search and history.back(), which have no built-in.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

query = "#query"

main! = |_args| {
	{ browser, page } = Support.open!("navigation", "#search")?

	# Typing replaces the URL in place, percent-encoded.
	Playwright.fill!(page, "#search", "first")?
	Playwright.fill!(page, "#search", "hats on")?
	replaced = Playwright.evaluate!(page, "location.search")?
	if replaced != "?q=hats%20on" {
		Err(ReplaceUrlWrong(replaced))?
	}

	# push_url changes the URL and keeps the model: the rendered query
	# survives the push.
	Playwright.click!(page, "#push")?
	pushed = (Playwright.evaluate!(page, "location.search")?, Playwright.text_content!(page, query)?)
	if pushed != ("?demo=push", "Current query: hats on") {
		Err(PushUrlWrong(pushed))?
	}

	# Replace on top of the pushed entry, so Back has something visible to
	# return from...
	Playwright.fill!(page, "#search", "second")?

	# ...then Back: a real popstate lands on the first entry (last replaced to
	# ?q=hats%20on) and DOM.on_url_change re-derives the query from it.
	_ = Playwright.evaluate!(page, "(history.back(), 'ok')")?
	Support.wait_for_text!(page, query, "Current query: hats on")?
	back_search = Playwright.evaluate!(page, "location.search")?
	if back_search != "?q=hats%20on" {
		Err(BackLandedElsewhere(back_search))?
	}

	# navigate is a full page load: the app re-initialises and the query is
	# gone (www/index.html passes empty flags).
	Playwright.click!(page, "#reload")?
	Support.wait_for_text!(page, query, "Current query: ")?
	reloaded = Playwright.evaluate!(page, "location.search")?

	Playwright.close!(browser)?

	if reloaded == "?reloaded=1" {
		Ok({})
	} else {
		Err(NavigateWrong(reloaded))
	}
}
