# Real-browser E2E: the counter example in Chromium. Two real clicks on "+"
# must render "+2-", the same assertion the fake-DOM harness makes, now with
# the browser's own event dispatch and DOM.
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

	Playwright.navigate!(page, "${base}/counter/")?
	Playwright.wait_for!(page, "#app button", Visible)?

	# <div><button>+</button>0<button>-</button></div>
	Playwright.click!(page, "#app button:first-of-type")?
	Playwright.click!(page, "#app button:first-of-type")?
	after_plus = Playwright.text_content!(page, "#app div")?

	Playwright.click!(page, "#app button:last-of-type")?
	after_minus = Playwright.text_content!(page, "#app div")?

	Playwright.close!(browser)?

	if after_plus == "+2-" and after_minus == "+1-" {
		Ok({})
	} else {
		Err(WrongCounterText(after_plus, after_minus))
	}
}
