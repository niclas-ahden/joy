# Real-browser E2E: the pointer example in Chromium, driven by the raw mouse
# primitives so the browser itself synthesizes the PointerEvents (the fake
# harness builds them by hand). Coordinates come from bounding_box!, so the
# drag provably happens inside the pad, and Playwright's keyboard state
# (Shift held across a click) must arrive as the event's shift modifier.
# Exact coordinates are not asserted, that is the fake harness's job, and
# formatting of F64s is not this test's business.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

position = "#position"
moves = "#moves"
shift_clicks = "#shift-clicks"

main! = |_args| {
	{ browser, page } = Support.open!("pointer", "#pad")?
	box = Playwright.bounding_box!(page, "#pad")?

	# Hovering (no button held) is not a drag: nothing counts, nothing grabs.
	Playwright.mouse_move!(page, box.x + 30, box.y + 20)?
	hovered = (Playwright.text_content!(page, position)?, Playwright.text_content!(page, moves)?)
	if !(hovered.0.contains("(idle)") and hovered.1 == "Moves: 0") {
		Err(HoverGrabbed(hovered))?
	}

	# Press to grab: the press coordinates land in the model and the pad
	# reports dragging.
	Playwright.mouse_down!(page)?
	at_press = Playwright.text_content!(page, position)?
	if !at_press.contains("(dragging)") {
		Err(PressDidNotGrab(at_press))?
	}

	# Drag in five steps: five real pointermoves with the button held, each
	# counted, and the tracked point actually moves.
	Playwright.mouse_move_with_steps!(page, box.x + 130, box.y + 80, 5)?
	dragged = (Playwright.text_content!(page, position)?, Playwright.text_content!(page, moves)?)
	if !(dragged.0.contains("(dragging)") and dragged.0 != at_press and dragged.1 == "Moves: 5") {
		Err(DragNotTracked(dragged))?
	}

	# Release to drop. Moving afterwards must not count.
	Playwright.mouse_up!(page)?
	Playwright.mouse_move!(page, box.x + 60, box.y + 60)?
	released = (Playwright.text_content!(page, position)?, Playwright.text_content!(page, moves)?)
	if !(released.0.contains("(idle)") and released.1 == "Moves: 5") {
		Err(ReleaseDidNotDrop(released))?
	}

	# Shift held across a press: the modifier crosses as part of the event.
	Playwright.key_down_targetless!(page, Shift)?
	Playwright.mouse_down!(page)?
	Playwright.mouse_up!(page)?
	Playwright.key_up_targetless!(page, Shift)?
	shifted = Playwright.text_content!(page, shift_clicks)?

	Playwright.close!(browser)?

	if shifted == "Shift-clicks: 1" {
		Ok({})
	} else {
		Err(ShiftNotSeen(shifted))
	}
}
