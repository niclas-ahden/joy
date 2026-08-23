# Real-browser E2E: the ports example in Chromium. Ports are Joy's JS-interop
# surface, so this test is deliberately evaluate!-driven: it plays the part
# of the embedding page, using the `app` handle www/index.html exposes.
# Incoming, sendPort drives the subscribed port and each send ticks the
# model. Outgoing, Port.send must reach a handler registered with onPort. At
# level 3 the app drops the subscription, so a further send must be ignored.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

level = "#level"

main! = |_args| {
	{ browser, page } = Browser.open!("ports", "#app pre")?

	# The embedder's side of the outgoing port, collecting what Port.send
	# delivers.
	_ = page.evaluate!("(window.__levels = [], app.onPort('level', (v) => window.__levels.push(v)), 'ok')")?

	# Each send is a Tick: subscription decoding, update and render all run
	# off the JS call.
	_ = page.evaluate!("(app.sendPort('excitement', ''), 'ok')")?
	assert!(page.find(level).has_text("Your excitement level for Roc: 1"))?

	_ = page.evaluate!("(app.sendPort('excitement', ''), 'ok')")?
	_ = page.evaluate!("(app.sendPort('excitement', ''), 'ok')")?
	assert!(page.find(level).has_text("Your excitement level for Roc: 3"))?
	assert!(page.find("#capped").has_text("Whoah, let's calm down! I've stopped the ticker."))?

	# At 3 the subscription is gone, so this send must fall on deaf ears.
	_ = page.evaluate!("(app.sendPort('excitement', ''), 'ok')")?
	assert!(page.find(level).has_text("Your excitement level for Roc: 3"))?

	# The outgoing port delivered every tick, in order, to the JS handler.
	levels = page.evaluate!("window.__levels.join(',')")?

	browser.close!()?

	if levels == "1,2,3" {
		Ok({})
	} else {
		Err(OutgoingPortWrong(levels))
	}
}
