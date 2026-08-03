# Real-browser E2E: the events_input example in Chromium. Playwright's fill
# drives the browser's own input events through a real <textarea>; the app
# must echo the value into its <p> (typed value events, big-string path).
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

	Playwright.navigate!(page, "${base}/events_input/")?
	Playwright.wait_for!(page, "#app textarea", Visible)?

	typed = "hello from a real browser ✓"
	Playwright.fill!(page, "#app textarea", typed)?
	echoed = Playwright.text_content!(page, "#app p")?

	Playwright.close!(browser)?

	if echoed == typed {
		Ok({})
	} else {
		Err(InputNotEchoed(echoed))
	}
}
