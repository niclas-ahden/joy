# Real-browser E2E: a click that passes two handlers on its way up, where the
# first changes what the second's element shows. Only a browser bubbles a
# real click through the page, and decides the way before any listener runs.
# tests/apps/rows.roc has rows a click selects, each with a button that
# deletes it. Each handler must get the message it had in the view the click
# happened in: deleting a row never selects another one.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("rows", "#plain-del-beta")?

	# A plain list gives the deleted row's element to the next row.
	page.find("#plain-del-beta").click!()?
	assert!(page.find("#log").has_text("deleted beta, selected beta"))?
	assert!(page.find_all("#plain li").has_count(3))?

	# The last row's element is removed while the click is on its way.
	page.find("#plain-del-delta").click!()?
	assert!(page.find("#log").has_text("deleted beta, selected beta, deleted delta, selected delta"))?

	# A keyed list removes the element of the row it deletes.
	page.find("#keyed-del-beta").click!()?
	assert!(page.find("#log").has_text("deleted beta, selected beta, deleted delta, selected delta, deleted beta, selected beta"))?
	assert!(page.find_all("#keyed li").has_count(3))?

	# The handler above the button is the one of the view the click happened
	# in, which said "plain".
	page.find("#flip").click!()?
	assert!(page.find("#log").has_text("deleted beta, selected beta, deleted delta, selected delta, deleted beta, selected beta, flipped, saw plain"))?

	browser.close!()?
	Ok({})
}
