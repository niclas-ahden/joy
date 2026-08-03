# Real-browser E2E: click propagation in Chromium. A browser is the only
# place the stop_propagation flag is observable end to end, since the
# fake-DOM harness calls a node's listener directly and never walks
# ancestors. Two clicks on the stop_propagation example: the first bubbles up
# to the outer div, the second must not.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	# A path dep until roc-playwright is released: needs a ../roc-playwright
	# checkout next to this repo (see e2e.roc).
	playwright: "../../../roc-playwright/package/main.roc",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import playwright.Playwright

hooks = {
	new: Cmd.new_str,
	args: Cmd.args_str,
	spawn_grouped!: Cmd.spawn_grouped!,
	write_stdin!: Cmd.Child.write_stdin!,
	read_stdout!: Cmd.Child.read_stdout!,
	kill!: Cmd.Child.kill!,
}

main! = |_args| {
	base = Env.var_str!(OsStr.from_str("JOY_E2E_URL")).ok_or("http://127.0.0.1:8787")
	{ browser, page } = Playwright.launch_page!(hooks, Chromium(DefaultChannel))?

	Playwright.navigate!(page, "${base}/stop_propagation/")?
	Playwright.wait_for!(page, "#app button", Visible)?

	# A plain on_click: the button's handler runs and the click travels on to
	# the outer div, so both counters move.
	Playwright.click!(page, "#bubbles")?
	after_bubble = Playwright.text_content!(page, "#counts")?

	# stop_propagation: the button's own handler still runs, but the outer
	# div never sees the click, so only the inner counter moves. This is the
	# assertion that fails if the flag is dropped anywhere along the way
	# (Roc constructor, host command buffer, or runtime.js).
	Playwright.click!(page, "#stops")?
	after_stop = Playwright.text_content!(page, "#counts")?

	Playwright.close!(browser)?

	if after_bubble == "outer 1, inner 1" and after_stop == "outer 1, inner 2" {
		Ok({})
	} else {
		Err(WrongCounts(after_bubble, after_stop))
	}
}
