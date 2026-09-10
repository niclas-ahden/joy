import pf.Cmd
import pf.Env
import playwright.Playwright exposing [assert!]

## Shared plumbing for the browser tests in this directory. Every test is a
## standalone app (see run.roc) driving its own browser, so the launch and
## navigate dance would otherwise repeat in each file. JOY_BROWSER picks the
## engine (chromium, the default, firefox or webkit), set by e2e.roc from its
## --browser flag. Assertions stay in the
## tests, through Playwright's assert!: each claim re-checks the page until it
## holds or the page's timeout expires, so the tests need no polling of their
## own.
Browser :: [].{
	open! = |app_name, ready| {
		base = Env.var_str!("JOY_E2E_URL") ?? "http://127.0.0.1:8787"
		browser_type = match Env.var_str!("JOY_BROWSER") ?? "chromium" {
			"firefox" => Firefox
			"webkit" => WebKit
			_ => Chromium(DefaultChannel)
		}
		{ browser, page } = Playwright.launch_page_with!(
			{ new: Cmd.new_str, spawn!: Cmd.spawn_leashed! },
			{ browser_type, timeout: TimeoutMilliseconds(10000) },
		)?
		page.navigate!("${base}/${app_name}/")?
		assert!(page.find(ready).is_visible())?
		Ok({ browser, page })
	}
}
