# Real-browser E2E: the modal example in Chromium. The fake DOM can only
# approximate <dialog> semantics, so this is exactly the coverage a real
# browser adds: showModal/close driven from update!, with visibility checked
# by the browser itself.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("modal", "#open")?

	# The dialog starts closed: its contents must not be visible.
	assert!(page.find("#prompt").is_hidden())?

	# "Delete everything" -> update! calls DOM.show_modal!("#confirm").
	page.find("#open").click!()?
	assert!(page.find("#prompt").is_visible())?

	# "Yes, delete" -> update! closes the dialog and counts the confirm.
	page.find("#yes").click!()?
	assert!(page.find("#prompt").is_hidden())?

	assert!(page.find("#counts").has_text("Opened 1, confirmed 1"))?

	browser.close!()?
	Ok({})
}
