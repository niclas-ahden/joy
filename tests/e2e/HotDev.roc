import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Sleep
import Browser

## Shared plumbing for the browser tests of hot reloading, which run ./joy dev on
## a copy of a project (tests/e2e/hot_project or hot_pages) in build/<opt>/, with
## the CLI e2e.roc builds beside it. A build takes as long as it takes and a page
## that reloads has no answer meanwhile, so these wait by asking again, where
## assert! could time out.
HotDev :: [].{
	## Whether the CLI is built: it is not on Windows, which has no host for it
	## yet, and a test then passes without running.
	has_cli! = || {
		opt = Env.var_str!("JOY_OPT") ?? "speed"
		Path.utf8("build/${opt}/joy-cli").is_file!() ?? False
	}

	## Run ./joy dev with `args` on a fresh copy of `fixture`, named `name`, and open
	## a browser.
	start! = |name, fixture, args, port| {
		opt = Env.var_str!("JOY_OPT") ?? "speed"
		dir = "build/${opt}/${name}"
		_ = shell("rm -rf ${dir} && cp -r tests/e2e/${fixture} ${dir}").run!()?
		HotDev.run!(dir, args, port)
	}

	## An empty folder at `dir`, for a test to write its own project in.
	fresh! = |dir| {
		_ = shell("rm -rf ${dir} && mkdir -p ${dir}").run!()?
		Ok({})
	}

	## Run ./joy dev with `args` on the project at `dir`, a folder of build/<opt>/, and
	## open a browser.
	run! = |dir, args, port| {
		dev = shell("cd ${dir} && exec ../joy-cli dev --port ${port} ${args}").stdout(Null).stderr(Null).spawn_leashed!()?
		{ browser, page } = Browser.launch!()?
		Ok({ dir, dev, browser, page, url: "http://localhost:${port}" })
	}

	## Close the browser and ./joy dev.
	stop! = |started| {
		started.browser.close!()?
		started.dev.close!() ?? {}
		Ok({})
	}

	## Replace `from` in a file, which ./joy dev then notices.
	edit! = |file, from, to| {
		text = Path.utf8(file).read_utf8!()?
		if !text.contains(from) {
			return Err(NothingToEdit({ file, from }))
		}
		Path.utf8(file).write_utf8!(text.replace_first(from, to))
	}

	## Go to `url` once `ready` is on the page there. The first builds take a while.
	open! = |page, url, ready| {
		var $left = patience
		while $left > 0 {
			match page.navigate!(url) {
				Ok(_) =>
					if answers!(page, "String(document.querySelector('${ready}') !== null)", "true") {
						return Ok({})
					}

				Err(_) => {}
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(NeverOpened(url))
	}

	## Wait for an element to hold `text`, on a page with its apps mounted.
	shows! = |page, selector, text| {
		var $left = patience
		while $left > 0 {
			if answers!(page, "String(document.querySelector('${selector}')?.textContent)", text) {
				return Ok({})
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(NeverShown({ selector, text }))
	}

	## Wait for roc's report over the page to say `text`.
	reports! = |page, text| {
		var $left = patience
		while $left > 0 {
			if answers!(page, "String(document.querySelector('joy-build-report')?.shadowRoot.querySelector('pre').textContent.includes('${text}'))", "true") {
				return Ok({})
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(NoReport(text))
	}

	## Wait until the report is gone.
	no_report! = |page| {
		var $left = patience
		while $left > 0 {
			if answers!(page, "String(document.querySelector('joy-build-report') === null)", "true") {
				return Ok({})
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(ReportStayed)
	}

	## Wait for the page to take a stylesheet's new color.
	styled! = |page, color| {
		var $left = patience
		while $left > 0 {
			if answers!(page, "getComputedStyle(document.body).color", color) {
				return Ok({})
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(NeverStyled(color))
	}

	## Mark the document, so a test can tell later whether it is still the same one.
	mark! = |page| {
		_ = page.evaluate!("(window.samePage = 'yes', 'marked')")?
		Ok({})
	}

	## Fails unless the document is the one `mark!` marked.
	same_page! = |page| same!(page.evaluate!("String(window.samePage)")?, "yes")

	## Wait for a page load, which clears the mark.
	reloaded! = |page| {
		var $left = patience
		while $left > 0 {
			if answers!(page, "String(window.samePage)", "undefined") {
				return Ok({})
			}
			Sleep.millis!(200)?
			$left = $left - 1
		}
		Err(NeverReloaded)
	}

	## Fails unless `got` is `want`.
	same! = |got, want| if got == want Ok({}) else Err(NotSame({ got, want }))

	## Let builds and events settle, for a test that shows nothing happened.
	quiet! = || Sleep.millis!(3_000)
}

## Tries at 200 ms each.
patience = 300

## Run a command line, which sets the working directory for ./joy dev.
shell = |line| Cmd.new(OsStr.from_str("bash")).args(["-c", line].map(OsStr.from_str))

## Whether the page, with its apps mounted, gives `want` for an expression. A page
## that is reloading gives nothing.
answers! = |page, expression, want| {
	mounted =
		match page.evaluate!("String(document.querySelector('[data-joy-mounted], body[data-ready]') !== null)") {
			Ok(answer) => answer == "true"
			Err(_) => False
		}
	match page.evaluate!(expression) {
		Ok(answer) => mounted and answer == want
		Err(_) => False
	}
}
