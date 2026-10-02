app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.27.0/HZanbveSUDoJF8LypR663eH7PpaKEKG36eErEQzmV1Qs.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
}

import playwright.Playwright
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("deep", "#app button")?
	_ = page.evaluate!("0")?
	helper!(page)?
	browser.close!()?
	Ok({})
}

helper! = |page| {
	_ = page.evaluate!("1")?
	built = page.evaluate!("2")?
	if built != "(ok)" {
		Err(BuildFailed(built))?
	}
	Ok({})
}
