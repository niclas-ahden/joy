# Real-browser E2E: the ports example in Chromium. Ports are Joy's JS-interop
# surface, so this test is deliberately evaluate!-driven: it plays the part
# of the embedding page, using the `app` handle www/index.html exposes.
# Incoming, sendPort drives the subscribed port and each send ticks the
# model. Outgoing, Port.send must reach a handler registered with onPort. At
# level 3 the app drops the subscription, so a further send must be ignored.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

level = "#level"

main! = |_args| {
	{ browser, page } = Support.open!("ports", "#app pre")?

	# The embedder's side of the outgoing port, collecting what Port.send
	# delivers.
	_ = Playwright.evaluate!(page, "(window.__levels = [], app.onPort('level', (v) => window.__levels.push(v)), 'ok')")?

	# Each send is a Tick: subscription decoding, update and render all run
	# off the JS call.
	_ = Playwright.evaluate!(page, "(app.sendPort('excitement', ''), 'ok')")?
	Support.wait_for_text!(page, level, "Your excitement level for Roc: 1")?

	_ = Playwright.evaluate!(page, "(app.sendPort('excitement', ''), 'ok')")?
	_ = Playwright.evaluate!(page, "(app.sendPort('excitement', ''), 'ok')")?
	Support.wait_for_text!(page, level, "Your excitement level for Roc: 3")?
	Support.expect_text!(
		page,
		"#capped",
		"Whoah, let's calm down! I've stopped the ticker.",
		|got| CapMessageMissing(got),
	)?

	# At 3 the subscription is gone, so this send must fall on deaf ears.
	_ = Playwright.evaluate!(page, "(app.sendPort('excitement', ''), 'ok')")?
	Support.expect_text!(
		page,
		level,
		"Your excitement level for Roc: 3",
		|got| SendAfterUnsubscribeTicked(got),
	)?

	# The outgoing port delivered every tick, in order, to the JS handler.
	levels = Playwright.evaluate!(page, "window.__levels.join(',')")?

	Playwright.close!(browser)?

	if levels == "1,2,3" {
		Ok({})
	} else {
		Err(OutgoingPortWrong(levels))
	}
}
