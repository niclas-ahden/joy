# Real-browser E2E: the project ./joy init starts from the spa-pages-expanded
# template, as someone new meets it under ./joy dev. The notes are the app's
# and stay while pages come and go, what is typed on a page is the page's and
# does not, a note has a URL of its own, and the Quote page shows what the
# quote server answers, which the test stands in for.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
}

import pf.Env
import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	opt = Env.var_str!("JOY_OPT") ?? "speed"
	dir = "build/${opt}/spa_pages_expanded_template"
	HotDev.init!(dir, "spa-pages-expanded")?

	started = HotDev.run!(dir, "", "8782")?
	{ page, url, .. } = started
	HotDev.open!(page, "${url}/", "nav a")?
	HotDev.shows!(page, "h1", "Notes")?
	assert!(page.has_title("Notes - Joy app"))?
	HotDev.shows!(page, "main [aria-live]", "3 of 3 notes")?

	# A new note joins the list, and the field is empty again.
	HotDev.mark!(page)?
	page.find("#note").fill!("Water the plants")?
	page.find("main form button").click!()?
	HotDev.shows!(page, "main [aria-live]", "4 of 4 notes")?
	HotDev.same!(page.evaluate!("document.getElementById('note').value")?, "")?

	# The search waits for a pause in the typing, and does not mind capitals.
	page.find("#search").fill!("ABOUT")?
	HotDev.shows!(page, "main [aria-live]", "1 of 4 notes")?
	assert!(page.find(".notes li").has_text("Read the About page"))?

	# What is typed belongs to the page: it is gone after a visit elsewhere.
	# The notes belong to the app, and stay.
	page.find("nav a:nth-child(3)").click!()?
	HotDev.shows!(page, "h1", "About")?
	assert!(page.has_title("About - Joy app"))?
	page.find("nav a:nth-child(1)").click!()?
	HotDev.shows!(page, "main [aria-live]", "4 of 4 notes")?
	HotDev.same!(page.evaluate!("document.getElementById('search').value")?, "")?
	HotDev.same_page!(page)?

	# A note has a page and a URL of its own.
	page.find(".notes li:nth-child(2) a").click!()?
	HotDev.shows!(page, "h1", "Note 2")?
	assert!(page.has_title("Note 2 - Joy app"))?
	HotDev.same!(page.evaluate!("location.pathname")?, "/notes/2")?

	# Removing it goes back to the list, and Back does not lead to the note
	# that is gone.
	page.find("main button").click!()?
	HotDev.shows!(page, "main [aria-live]", "3 of 3 notes")?
	HotDev.same!(page.evaluate!("location.pathname")?, "/")?
	_ = page.evaluate!("(history.back(), 'back')")?
	HotDev.shows!(page, "h1", "Notes")?
	HotDev.same_page!(page)?

	# A URL of the app opens its page, as a link someone shared or a refresh
	# asks for it.
	HotDev.open!(page, "${url}/notes/1", "nav a")?
	HotDev.shows!(page, "h1", "Note 1")?
	HotDev.open!(page, "${url}/notes/99", "nav a")?
	HotDev.shows!(page, "h1", "No such note")?
	HotDev.open!(page, "${url}/no/such/page", "nav a")?
	HotDev.shows!(page, "main p", "There is no page here.")?
	assert!(page.has_title("Not found - Joy app"))?

	# The Quote page asks for a quote each time it is opened.
	page.with_routes!(
		[{ pattern: quotes, method: AnyMethod, action: answer(200, "[\"A quote from the test\"]") }],
		|routed| {
			routed.find("nav a:nth-child(2)").click!()?
			HotDev.shows!(routed, "blockquote", "A quote from the test")?
			assert!(routed.has_title("Quote - Joy app"))?
			Ok({})
		},
	)?
	page.with_routes!(
		[{ pattern: quotes, method: AnyMethod, action: answer(500, "no") }],
		|routed| {
			routed.find("main button").click!()?
			HotDev.shows!(routed, ".problem", "The server answered 500.")?
			Ok({})
		},
	)?

	HotDev.stop!(started)
}

## The quote server's address, and an answer the test gives in its place. The
## header lets a page of another origin read it, as the real server's does.
quotes : Str
quotes = "https://ron-swanson-quotes.herokuapp.com/**"

answer = |status, body|
	Fulfill({ status, headers: [{ name: "content-type", value: "application/json" }, { name: "access-control-allow-origin", value: "*" }], body: Str.to_utf8(body) })
