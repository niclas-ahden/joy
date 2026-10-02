# Controlled inputs in a real browser, every kind: a change the update
# refuses snaps the control back to the model, a normalizing update writes
# its own version back, and a keystroke in the middle of a value leaves
# the caret where it was, whether accepted (the property is not rewritten)
# or refused or normalized (the runtime puts the caret back). The fake-DOM
# harness (tests/check_form.mjs) owns the work budgets; this proves the
# browser's side of the contract, in whichever engine JOY_BROWSER names.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("form", "#t0")?

	# Text: accepted text lands, a refused "!" is snapped back.
	page.fill!("#t0", "hello")?
	assert!(page.find("#t0").has_value("hello"))?
	page.key_press!("#t0", Digit1, [Shift])?
	assert!(page.find("#t0").has_value("hello"))?

	# The caret survives an accepted keystroke mid-value.
	place_caret!(page, "#t0", 2)?
	page.key_press!("#t0", KeyX, [])?
	assert!(page.find("#t0").has_value("hexllo"))?
	expect_caret!(page, "#t0", "3")?

	# And a refused one: the snap-back would leave the caret at the end, so
	# the runtime moves it back by what was refused.
	place_caret!(page, "#t0", 2)?
	page.key_press!("#t0", Digit1, [Shift])?
	assert!(page.find("#t0").has_value("hexllo"))?
	expect_caret!(page, "#t0", "2")?

	# A normalizing update: the code field uppercases and drops spaces. Typed
	# text lands normalized, a mid-value letter is rewritten in place with
	# the caret after it, and a dropped space leaves the caret where it was.
	page.fill!("#code", "ab c")?
	assert!(page.find("#code").has_value("ABC"))?
	place_caret!(page, "#code", 1)?
	page.key_press!("#code", KeyX, [])?
	assert!(page.find("#code").has_value("AXBC"))?
	expect_caret!(page, "#code", "2")?
	page.key_press!("#code", Space, [])?
	assert!(page.find("#code").has_value("AXBC"))?
	expect_caret!(page, "#code", "2")?

	# Textarea, by fill: on Firefox a fill ends a composition before the
	# input that carries the text, the order tests/check_form.mjs models.
	page.fill!("#notes", "hi")?
	assert!(page.find("#notes").has_value("hi"))?
	page.fill!("#notes", "hi!")?
	assert!(page.find("#notes").has_value("hi"))?

	# Checkbox: checking is accepted, unchecking refused. A plain click, not
	# uncheck!, because Playwright's uncheck! verifies the state flipped.
	page.check!("#c0")?
	assert!(page.find("#c0").is_checked())?
	page.click!("#c0")?
	assert!(page.find("#c0").is_checked())?

	# Radio: green is accepted, blue refused, and the group snaps back.
	page.click!("#color-green")?
	assert!(page.find("#color-green").is_checked())?
	assert!(page.find("#color-red").is_unchecked())?
	page.click!("#color-blue")?
	assert!(page.find("#color-green").is_checked())?
	assert!(page.find("#color-blue").is_unchecked())?

	# Select: M is accepted, XL refused. Picked the way assistive tech and
	# scripts do, by value plus a change event.
	_ = Playwright.evaluate!(page, pick("m"))?
	assert!(page.find("#size").has_value("m"))?
	_ = Playwright.evaluate!(page, pick("xl"))?
	assert!(page.find("#size").has_value("m"))?

	# Number: in range lands, out of range snaps back.
	page.fill!("#qty", "5")?
	assert!(page.find("#qty").has_value("5"))?
	page.key_press!("#qty", Digit0, [])?
	assert!(page.find("#qty").has_value("5"))?

	browser.close!()?
	Ok({})
}

pick : Str -> Str
pick = |val|
	"(() => { const s = document.querySelector('#size'); s.value = '${val}'; s.dispatchEvent(new Event('change', { bubbles: true })); return s.value })()"

# Focus the field and put a collapsed caret at the offset.
place_caret! = |page, selector, offset| {
	_ = Playwright.evaluate!(page, "(() => { const i = document.querySelector('${selector}'); i.focus(); i.setSelectionRange(${offset.to_str()}, ${offset.to_str()}); return 'ok' })()")?
	Ok({})
}

expect_caret! = |page, selector, want| {
	caret = Playwright.evaluate!(page, "String(document.querySelector('${selector}').selectionStart)")?
	if caret == want {
		Ok({})
	} else {
		Err(CaretMoved({ selector, want, got: caret }))
	}
}
