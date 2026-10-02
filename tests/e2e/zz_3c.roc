app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
}

import pf.Cmd
import playwright.Playwright

main! = |_args| {
	{ browser, page } = Playwright.launch_page_with!(
		{ new: Cmd.new_str, spawn!: Cmd.spawn_leashed! },
		{ browser_type: Firefox, timeout: TimeoutMilliseconds(10000) },
	)?
	helper!(page)?
	browser.close!()?
	Ok({})
}

helper! = |page| {
	_ = page.evaluate!("1")?
	built = page.evaluate!("2")?
	if built != "(ok)" {
		Err(BuildFailed)?
	}
	Ok({})
}
