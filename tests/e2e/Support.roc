import pf.Cmd
import pf.Env
import pf.Sleep
import playwright.Playwright
import spec.Wait

## Shared plumbing for the browser tests in this directory. Every test is a
## standalone app (see run.roc) driving its own Chromium, so the launch and
## navigate dance would otherwise repeat in each file. Assertions stay in the
## tests: each one fails with a tag carrying what it actually saw.
Support :: [].{

	## Launch a headless Chromium on one of the built apps: open!("counter",
	## "#app button") opens ${JOY_E2E_URL}/counter/ and returns once `ready` is
	## visible, which is when the wasm app has booted and rendered. e2e.roc
	## exports JOY_E2E_URL, and the fallback matches its default port so a
	## single test can be run by hand against a server e2e.roc left behind.
	open! = |app_name, ready| {
		base = Env.var_str!("JOY_E2E_URL") ?? "http://127.0.0.1:8787"
		hooks = {
			new: Cmd.new_str,
			args: Cmd.args_str,
			spawn_grouped!: Cmd.spawn_grouped!,
			write_stdin!: Cmd.Child.write_stdin!,
			read_stdout!: Cmd.Child.read_stdout!,
			kill!: Cmd.Child.kill!,
		}
		{ browser, page } = Playwright.launch_page!(hooks, Chromium(DefaultChannel))?
		Playwright.navigate!(page, "${base}/${app_name}/")?
		Playwright.wait_for!(page, ready, Visible)?
		Ok({ browser, page })
	}

	## Read a selector's text and fail unless it is exactly `want`. The tag
	## stays in the test: `to_err` names what the assertion proves and carries
	## what the browser actually showed, e.g.
	## `expect_text!(page, keys, "Keys seen: 2", |got| EscapeNotCounted(got))`.
	expect_text! = |page, selector, want, to_err| {
		got = Playwright.text_content!(page, selector)?
		if got == want {
			Ok({})
		} else {
			Err(to_err(got))
		}
	}

	## Poll a selector's text until it equals `want`. Joy renders synchronously
	## inside event dispatch, so a read right after click! or key_press! never
	## needs this. It is for renders waiting on async work (timers, fetch,
	## WebCrypto, popstate). Gives up after ~5s, carrying the last text seen.
	##
	## The condition's errors are collapsed to two closed tags: every call on a
	## Page shares one error union through its type parameter, so letting the
	## read's own errors escape through ConditionNotMet would make that union
	## contain itself.
	wait_for_text! = |page, selector, want|
		Wait.until!(
			{ sleep!: Sleep.millis! },
			|_| {
				match Playwright.text_content!(page, selector) {
					Ok(got) if got == want => Ok({})
					Ok(got) => Err(TextIs(got))
					Err(_) => Err(CouldNotReadText(selector))
				}
			},
			{ max_attempts: 50, delay_ms: 100 },
		)
}
