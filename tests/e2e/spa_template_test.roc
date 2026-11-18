# Real-browser E2E: the project ./joy init starts from the spa template, as
# someone new meets it under ./joy dev. Its links switch pages in place, Back
# returns, a URL of the app opens its page, and a click that asks the browser
# for a new tab is left to the browser.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
}

import pf.Env
import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	opt = Env.var_str!("JOY_OPT") ?? "speed"
	dir = "build/${opt}/spa_template"
	HotDev.init!(dir, "spa")?

	started = HotDev.run!(dir, "", "8778")?
	{ page, url, .. } = started
	HotDev.open!(page, "${url}/", "nav a")?
	HotDev.shows!(page, "h1", "Home")?
	assert!(page.has_title("Home - Joy app"))?

	# A link to the page on screen leaves the page and the history as they are.
	HotDev.mark!(page)?
	page.find("main button:nth-of-type(2)").click!()?
	page.find("main button:nth-of-type(2)").click!()?
	HotDev.same!(page.evaluate!(count)?, "2")?
	entries = page.evaluate!("String(history.length)")?
	page.find("nav a:nth-child(1)").click!()?
	HotDev.same!(page.evaluate!(count)?, "2")?
	HotDev.same!(page.evaluate!("String(history.length)")?, entries)?

	# So does a URL that still names the page, as a place on the page does.
	_ = page.evaluate!("(location.hash = 'top', 'there')")?
	_ = page.evaluate!("(history.back(), 'back')")?
	HotDev.same!(page.evaluate!("location.pathname + location.hash")?, "/")?
	HotDev.same!(page.evaluate!(count)?, "2")?

	# A link to another page switches the page in place, and changes the URL
	# and the title.
	page.find("nav a:nth-child(2)").click!()?
	HotDev.shows!(page, "h1", "About")?
	assert!(page.find("nav a.current").has_text("About"))?
	assert!(page.has_title("About - Joy app"))?
	HotDev.same!(page.evaluate!("location.pathname")?, "/about")?
	HotDev.same_page!(page)?

	# With Ctrl held, a click on a link asks for a new tab. The app takes no
	# message from it and leaves its default alone, so the browser opens one.
	HotDev.same!(page.evaluate!(ctrl_click_home)?, "false")?
	HotDev.shows!(page, "h1", "About")?

	# Back returns to the page before, in place.
	_ = page.evaluate!("(history.back(), 'back')")?
	HotDev.shows!(page, "h1", "Home")?
	assert!(page.has_title("Home - Joy app"))?
	HotDev.same_page!(page)?

	# A URL of the app opens its page, a deeper one too, as a link someone
	# shared or a refresh asks for it. A query and a fragment come along.
	HotDev.open!(page, "${url}/about/", "nav a")?
	HotDev.shows!(page, "h1", "About")?
	HotDev.open!(page, "${url}/about?from=menu#top", "nav a")?
	HotDev.shows!(page, "h1", "About")?
	HotDev.open!(page, "${url}/no/such/page", "nav a")?
	HotDev.shows!(page, "main p", "There is no page here.")?
	assert!(page.has_title("Not found - Joy app"))?

	HotDev.stop!(started)
}

## The count the Home page shows, between its two buttons.
count : Str
count = "document.querySelector('main button').nextSibling.textContent.trim()"

## Click the first link, Home, with Ctrl held, and answer whether a handler
## on the way up prevented the default. The listener on the window is the last
## to hear the click, and stops the browser from following the link itself.
ctrl_click_home : Str
ctrl_click_home =
	"(() => { let prevented = 'the click never arrived'; addEventListener('click', (e) => { prevented = String(e.defaultPrevented); e.preventDefault(); }, { once: true }); document.querySelector('nav a').dispatchEvent(new MouseEvent('click', { ctrlKey: true, bubbles: true, cancelable: true })); return prevented; })()"
