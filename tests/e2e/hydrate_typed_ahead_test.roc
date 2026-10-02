# What a visitor does to a server-rendered page before the app boots: the
# wasm is held back while they type, pick and tick, then let through. The
# claim keeps every change, and the app hears about each one through the
# control's own handler, so its model agrees with the page. A value the app
# refuses is refused like any typed value, and the field shows the model.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import pf.Sleep
import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	base = Browser.base_url!()
	{ browser, page } = Browser.launch!()?

	Playwright.with_routes!(page, [{ pattern: "**/app.wasm", method: AnyMethod, action: Hold }], |routed| {
		Playwright.navigate_with!(routed, { url: "${base}/hydrate_lab/", wait_until: Commit })?
		assert!(routed.find(".name").is_visible())?

		# The page is the server's alone: nothing has booted.
		Assert.eq(routed.evaluate!("String(document.getElementById('app').hasAttribute('data-booted'))")?, "false") ? |e| BootedTooEarly(Str.inspect(e))

		routed.fill!(".name", "Annie")?
		routed.fill!(".bio", "edited")?
		_ = routed.evaluate!("(document.querySelector('.size').value = 'l', 'ok')")?
		routed.check!(".red")?
		routed.uncheck!(".agree")?

		release_held!(routed, 100)?
		assert!(routed.find("#app[data-booted]").is_visible())?
		Ok({})
	})?

	assert!(page.find(".name").has_value("Annie"))?
	assert!(page.find(".bio").has_value("edited"))?
	Assert.eq(page.evaluate!("document.querySelector('.size').value")?, "l") ? |e| PickLost(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.querySelector('.red').checked) + ' ' + document.querySelector('.agree').checked")?, "true false") ? |e| TicksLost(Str.inspect(e))
	assert!(page.find(".echo").has_text("Annie|edited|l|red|no|0"))?
	Assert.eq(page.evaluate!("JSON.stringify(window.app.hydration())")?, "{\"claimed\":true,\"mismatch\":null}") ? |e| TypingAheadIsNoMismatch(Str.inspect(e))

	# The app keeps working from there.
	page.fill!(".name", "Anna")?
	assert!(page.find(".echo").has_text("Anna|edited|l|red|no|0"))?

	# A value the app refuses, typed before boot.
	Playwright.with_routes!(page, [{ pattern: "**/app.wasm", method: AnyMethod, action: Hold }], |routed| {
		Playwright.navigate_with!(routed, { url: "${base}/hydrate_lab/", wait_until: Commit })?
		assert!(routed.find(".name").is_visible())?
		routed.fill!(".name", "Ann!")?
		release_held!(routed, 100)?
		assert!(routed.find("#app[data-booted]").is_visible())?
		Ok({})
	})?
	assert!(page.find(".name").has_value("Ann"))?
	Assert.eq(page.evaluate!("document.querySelector('.echo').textContent")?, "Ann|First line\nsecond line|m|blue|yes|0") ? |e| RefusedValueReachedTheModel(Str.inspect(e))

	browser.close!()?
	Ok({})
}

## Let the held wasm through once the page has asked for it. The page asks
## after its runtime loads, which may be after the test is ready, so an
## empty hold is retried for a while.
release_held! = |page, attempts_left|
	match Playwright.release!(page, Continue) {
		Ok(_) => Ok({})
		Err(NoHeldRequest) if attempts_left > 0 => {
			Sleep.millis!(50)
			release_held!(page, attempts_left - 1)
		}
		Err(e) => Err(e)
	}
