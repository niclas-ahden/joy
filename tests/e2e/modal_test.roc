# Real-browser E2E: the modal example in Chromium. The fake DOM can only
# approximate <dialog> semantics, so this is exactly the coverage a real
# browser adds: showModal/close driven from update!, with visibility checked
# by the browser itself.
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

	Playwright.navigate!(page, "${base}/modal/")?
	Playwright.wait_for!(page, "#app button", Visible)?

	# The dialog starts closed: its contents must not be visible.
	before = Playwright.is_visible!(page, "#confirm p")?

	# "Delete everything" -> update! calls DOM.show_modal!("#confirm").
	Playwright.click!(page, "#app div > button")?
	Playwright.wait_for!(page, "#confirm p", Visible)?

	# "Yes, delete" -> update! closes the dialog and counts the confirm.
	Playwright.click!(page, "#confirm button:first-of-type")?
	Playwright.wait_for!(page, "#confirm p", Hidden)?

	counts = Playwright.text_content!(page, "#app > div > p")?

	Playwright.close!(browser)?

	if before == Bool.False and counts == "opened 1, confirmed 1" {
		Ok({})
	} else {
		Err(ModalFlowWrong(before, counts))
	}
}
