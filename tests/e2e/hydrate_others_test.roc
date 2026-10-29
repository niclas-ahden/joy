# What others do to a server-rendered page while the app loads: the wasm is
# held back, and meanwhile a password manager puts an icon next to a field
# and marks it, a widget draws into the page, a translator changes a text,
# and the visitor types. None of that is the server disagreeing with the
# client: the claim is clean, the others' nodes and attributes stay where
# they are, the text is the app's again, the typing reaches the app, and the
# app keeps patching around all of it afterwards.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
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
		# The loader defines its helpers right before it calls mount, which
		# starts watching the page before it asks for the wasm.
		Assert.eq(routed.evaluate!(mount_started)?, "started") ? |e| MountNeverStarted(Str.inspect(e))
		Assert.eq(routed.evaluate!(meddle)?, "ok") ? |e| CouldNotMeddle(Str.inspect(e))
		routed.fill!(".name", "Annie")?
		release_held!(routed, 100)?
		assert!(routed.find("#app[data-booted]").is_visible())?
		Ok({})
	})?

	Assert.eq(page.evaluate!("JSON.stringify(window.app.hydration())")?, "{\"claimed\":true,\"mismatch\":null}") ? |e| OthersAreNoMismatch(Str.inspect(e))
	Assert.eq(page.evaluate!(still_there)?, "icon tiles data-pm") ? |e| OthersWereRemoved(Str.inspect(e))
	Assert.eq(page.evaluate!("document.querySelector('.nudges').textContent")?, "nudges 0") ? |e| TextNotTakenBack(Str.inspect(e))
	assert!(page.find(".name").has_value("Annie"))?
	assert!(page.find(".echo").has_text("Annie|First line\nsecond line|m|blue|yes|0"))?

	# Patches around the others' nodes, with one more among the icons.
	_ = page.evaluate!("(document.querySelector('.icons').insertBefore(document.createElementNS('http://www.w3.org/2000/svg', 'circle'), document.querySelector('.icons').children[1]), 'ok')")?
	page.find(".rotate").click!()?
	page.find(".add").click!()?
	page.find(".rotate").click!()?
	page.find(".count").click!()?
	assert!(page.find(".echo").has_text("Annie|First line\nsecond line|m|blue|yes|1"))?
	Assert.eq(page.evaluate!(icon_names)?, "a n0 b") ? |e| IconsOutOfOrder(Str.inspect(e))
	Assert.eq(page.evaluate!(still_there)?, "icon tiles data-pm") ? |e| OthersRemovedLater(Str.inspect(e))

	browser.close!()?
	Ok({})
}

## Wait until the page's loader has called mount.
mount_started : Str
mount_started =
	\\new Promise((ok) => {
	\\  const check = () => (typeof window.labRoundTrip === 'function' ? ok('started') : setTimeout(check, 10));
	\\  check();
	\\})

## What others do while the wasm is held: an icon after the name field and an
## attribute on it, tiles drawn into the form, a translated text.
meddle : Str
meddle =
	\\(() => {
	\\  const name = document.querySelector('.name');
	\\  const icon = Object.assign(document.createElement('span'), { className: 'pm-icon' });
	\\  name.after(icon);
	\\  name.setAttribute('data-pm', 'filled');
	\\  document.querySelector('.forms').append(Object.assign(document.createElement('canvas'), { className: 'tiles' }));
	\\  document.querySelector('.nudges').firstChild.data = 'knuffar 0';
	\\  return 'ok';
	\\})()

## Which of the others' changes are still on the page.
still_there : Str
still_there =
	\\[
	\\  document.querySelector('.name + .pm-icon') ? 'icon' : 'no icon',
	\\  document.querySelector('.forms > .tiles') ? 'tiles' : 'no tiles',
	\\  document.querySelector('.name').hasAttribute('data-pm') ? 'data-pm' : 'no data-pm',
	\\].join(' ')

## The app's icons in page order.
icon_names : Str
icon_names = "[...document.querySelectorAll('.icons .icon')].map((g) => g.dataset.name).join(' ')"

## Let the held wasm through once the page has asked for it. The page asks
## after its runtime loads, which may be after the test is ready, so an
## empty hold is retried for a while.
release_held! = |page, attempts_left|
	match Playwright.release!(page, Continue) {
		Ok(_) => Ok({})
		Err(NoHeldRequest) if attempts_left > 0 => {
			Sleep.millis!(50)?
			release_held!(page, attempts_left - 1)
		}
		Err(e) => Err(e)
	}
