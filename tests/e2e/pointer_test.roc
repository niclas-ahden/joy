# Real-browser E2E: the pointer example in Chromium, driven by the raw mouse
# primitives so the browser itself synthesizes the PointerEvents (the fake
# harness builds them by hand). Coordinates come from bounding_box!, so the
# drag provably happens inside the pad, and Playwright's keyboard state
# (Shift held across a click) must arrive as the event's shift modifier.
# Exact coordinates are not asserted, that is the fake harness's job, and
# formatting of F64s is not this test's business.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

position = "#position"
moves = "#moves"

main! = |_args| {
	{ browser, page } = Browser.open!("pointer", "#pad")?
	box = page.find("#pad").bounding_box!()?

	# Hovering (no button held) is not a drag: nothing counts, nothing grabs.
	page.mouse_move!(box.x + 30, box.y + 20)?
	assert!(page.find(position).contains_text("(idle)"))?
	assert!(page.find(moves).has_text("Moves: 0"))?

	# Press to grab: the press coordinates land in the model and the pad
	# reports dragging.
	page.mouse_down!()?
	assert!(page.find(position).contains_text("(dragging)"))?
	at_press = page.find(position).text!()?

	# Drag in five steps: five real pointermoves with the button held, each
	# counted, and the tracked point actually moves away from the press.
	page.mouse_move_with_steps!(box.x + 130, box.y + 80, 5)?
	assert!(page.find(position).contains_text("(dragging)"))?
	assert!(page.find(position).not_has_text(at_press))?
	assert!(page.find(moves).has_text("Moves: 5"))?

	# Release to drop. Moving afterwards must not count.
	page.mouse_up!()?
	page.mouse_move!(box.x + 60, box.y + 60)?
	assert!(page.find(position).contains_text("(idle)"))?
	assert!(page.find(moves).has_text("Moves: 5"))?

	# Shift held across a press: the modifier crosses as part of the event.
	page.key_down_targetless!(Shift)?
	page.mouse_down!()?
	page.mouse_up!()?
	page.key_up_targetless!(Shift)?
	assert!(page.find("#shift-clicks").has_text("Shift-clicks: 1"))?

	browser.close!()?
	Ok({})
}
