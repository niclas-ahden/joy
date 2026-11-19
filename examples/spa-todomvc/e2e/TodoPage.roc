# Shared helpers for the browser tests. Not a test itself: the runner only
# spawns files ending in _test.roc, so this module can sit here. Launching is
# spelled out rather than borrowed from Joy's own tests, so this
# directory stands on its own.
import pf.Cmd
import pf.OsStr
import pf.Duration
import pf.Env
import playwright.Playwright exposing [assert!]

TodoPage :: [].{

	## Launch a browser on the app and wait for it to boot. The new-todo
	## input only exists once the wasm has rendered, so waiting for it
	## means every test starts against a running app.
	##
	## The URL under test comes from E2E_URL, which run.roc sets to its
	## worker's server. Without it, a test run on its own
	## (`roc e2e/add_test.roc`) targets ./joy dev on its default port.
	open! = |{}| open_at!("/")

	## The same, at a path of the app, like `/#/active`.
	open_at! = |path| {
		browser_type = match Env.var_str!("JOY_BROWSER") ?? "chromium" {
			"firefox" => Firefox
			"webkit" => WebKit
			_ => Chromium(DefaultChannel)
		}
		{ browser, page } = Playwright.launch_page_with!(
			{ new: Cmd.new, os_str: OsStr.from_str, spawn!: Cmd.Command.spawn_leashed!, millis: Duration.millis },
			{ browser_type, timeout: TimeoutMilliseconds(10000) },
		)?
		base = Env.var_str!("E2E_URL") ?? "http://localhost:8000"
		page.navigate!("${base}${path}")?
		assert!(page.find(".new-todo").is_visible())?
		Ok({ browser, page })
	}

	## Type a title into the new-todo input and press Enter.
	add! = |page, title| {
		page.find(".new-todo").fill!(title)?
		page.key_press!(".new-todo", Enter, [])
	}

	## Destroy the nth todo. The destroy button is display:none until the
	## row is hovered, so hover first like a user would.
	destroy! = |page, n| {
		page.find(row(n)).hover!()?
		page.find("${row(n)} .destroy").click!()
	}

	## Double-click the nth todo's label to start editing it. Dispatched
	## via JS because roc-playwright has no double-click yet. Joy binds the
	## handler on the label itself, so the synthetic event lands exactly
	## where a real double-click would.
	edit! = |page, n| {
		js =
			\\(() => {
			\\    const el = document.querySelector('${label(n)}');
			\\    if (!el) return 'ElementNotFound';
			\\    el.dispatchEvent(new MouseEvent('dblclick', {bubbles: true}));
			\\    return 'ok';
			\\})()
		result = page.evaluate!(js)?
		if result == "ok" {
			Ok({})
		} else {
			Err(NoTodoToEdit(n))
		}
	}

	## Selectors for the nth (1-based) todo in the list.
	row : U64 -> Str
	row = |n| ".todo-list li:nth-child(${n.to_str()})"

	label : U64 -> Str
	label = |n| "${row(n)} label"

	toggle : U64 -> Str
	toggle = |n| "${row(n)} .toggle"
}
