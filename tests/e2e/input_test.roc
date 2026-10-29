# Real-browser E2E: the events_input example in Chromium. Playwright's fill
# drives the browser's own input events through a real <textarea>; the app
# must echo the value into its <p> (typed value events, big-string path).
# Then a real form submission: on_submit must deliver the msg and stop the
# browser's default, or the page reloads and the model with it.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("events_input", "#app textarea")?

	typed = "hello from a real browser ✓"
	page.find("#app textarea").fill!(typed)?
	assert!(page.find("#draft").has_text(typed))?

	# A marker on the window outlives the submit only if the document does.
	_ = page.evaluate!("(() => { window.joyStillHere = 'yes'; return 'ok' })()")?
	page.find("form button").click!()?
	assert!(page.find("#saved").has_text("Saved: ${typed}"))?
	marker = page.evaluate!("String(window.joyStillHere)")?
	if marker != "yes" {
		Err(SubmitReloadedThePage(marker))?
	}

	browser.close!()?
	Ok({})
}
