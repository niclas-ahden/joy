# What others put in place of a server-rendered page's own nodes while the
# app loads, through the browser's real MutationObserver: a translator swaps
# a text for its translation, an extension wraps an element in a box of its
# own, another moves a node somewhere else, while a speed control is added
# next to the app's nodes. The translation and the box stand in for the
# page's nodes, so they go and the app's take their place back, and the
# moved node is still the page's, so it is not kept where it was moved to.
# The page shows each of the app's nodes once, and the speed control stays.
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

	# A translation and a wrapper: a clean claim, each node once.
	load_meddled!(page, "${base}/hydrate_lab/", stand_ins)?
	Assert.eq(page.evaluate!("JSON.stringify(window.app.hydration())")?, "{\"claimed\":true,\"mismatch\":null}") ? |e| StandInsReported(Str.inspect(e))
	Assert.eq(page.evaluate!(each_once)?, "nudges 0|no font|1 pre|no box|speed control") ? |e| StandInsKept(Str.inspect(e))
	page.find(".count").click!()?
	Assert.eq(page.evaluate!("document.querySelector('.echo').textContent.endsWith('|1') ? 'counted' : document.querySelector('.echo').textContent")?, "counted") ? |e| AppStoppedAnswering(Str.inspect(e))

	# A moved node: still the page's, so not kept where it was moved to.
	load_meddled!(page, "${base}/hydrate_lab/", move_shape)?
	Assert.eq(page.evaluate!(shape_once)?, "1 shape button|not in the forms") ? |e| MovedNodeKept(Str.inspect(e))

	browser.close!()?
	Ok({})
}

## Open `url` with the wasm held back, run `meddle` once mount is watching,
## then let the wasm through and wait for the app.
load_meddled! = |page, url, meddle|
	Playwright.with_routes!(page, [{ pattern: "**/app.wasm", method: AnyMethod, action: Hold }], |routed| {
		Playwright.navigate_with!(routed, { url, wait_until: Commit })?
		Assert.eq(routed.evaluate!(mount_started)?, "started") ? |e| MountNeverStarted(Str.inspect(e))
		Assert.eq(routed.evaluate!(meddle)?, "ok") ? |e| CouldNotMeddle(Str.inspect(e))
		release_held!(routed, 100)?
		assert!(routed.find("#app[data-booted]").is_visible())?
		Ok({})
	})

## Wait until the page's loader has called mount.
mount_started : Str
mount_started =
	\\new Promise((ok) => {
	\\  const check = () => (typeof window.labRoundTrip === 'function' ? ok('started') : setTimeout(check, 10));
	\\  check();
	\\})

## A translator swaps the nudge count's text for <font><font>, the way
## Chrome's translation does, an extension wraps the code block in a box of
## its own, and a speed control goes in front of the name field.
stand_ins : Str
stand_ins =
	\\(() => {
	\\  const outer = document.createElement('font');
	\\  const inner = document.createElement('font');
	\\  inner.textContent = 'knuffar 0';
	\\  outer.append(inner);
	\\  document.querySelector('.nudges').firstChild.replaceWith(outer);
	\\  const code = document.querySelector('pre.code');
	\\  const box = document.createElement('div');
	\\  box.className = 'ext-box';
	\\  code.replaceWith(box);
	\\  box.append(code);
	\\  document.querySelector('.name').before(document.createElement('vsc-controller'));
	\\  return 'ok';
	\\})()

## The nudge count's text, whether a translation is left in it, how many code
## blocks there are, whether the box is left, whether the speed control is.
each_once : Str
each_once =
	\\[
	\\  document.querySelector('.nudges').textContent,
	\\  document.querySelector('.nudges font') ? 'font' : 'no font',
	\\  document.querySelectorAll('pre.code').length + ' pre',
	\\  document.querySelector('.ext-box') ? 'box' : 'no box',
	\\  document.querySelector('vsc-controller + .name') ? 'speed control' : 'no speed control',
	\\].join('|')

## Another extension moves the shape button into the forms.
move_shape : Str
move_shape = "(document.querySelector('.forms').append(document.querySelector('button.shape')), 'ok')"

## How many shape buttons there are, and whether one is left in the forms.
shape_once : Str
shape_once =
	\\[
	\\  document.querySelectorAll('button.shape').length + ' shape button',
	\\  document.querySelector('.forms button.shape') ? 'in the forms' : 'not in the forms',
	\\].join('|')

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
