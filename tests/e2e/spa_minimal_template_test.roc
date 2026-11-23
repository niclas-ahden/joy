# Real-browser E2E: the project ./joy init starts from the spa-minimal
# template, as someone new meets it under ./joy dev: a count and two buttons.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
}

import pf.Env
import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	opt = Env.var_str!("JOY_OPT") ?? "speed"
	dir = "build/${opt}/spa_minimal_template"
	HotDev.init!(dir, "spa-minimal")?

	started = HotDev.run!(dir, "", "8781")?
	{ page, url, .. } = started
	HotDev.open!(page, "${url}/", "h1")?
	HotDev.shows!(page, "h1", "A Joy app")?
	assert!(page.has_title("Joy app"))?
	HotDev.same!(page.evaluate!(count)?, "0")?

	page.find("button[aria-label='One more']").click!()?
	page.find("button[aria-label='One more']").click!()?
	HotDev.same!(page.evaluate!(count)?, "2")?
	page.find("button[aria-label='One less']").click!()?
	HotDev.same!(page.evaluate!(count)?, "1")?

	HotDev.stop!(started)
}

## The count, between the two buttons.
count : Str
count = "document.querySelector('button').nextSibling.textContent.trim()"
