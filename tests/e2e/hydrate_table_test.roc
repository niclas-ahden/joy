# Markup the parser rewrites: the lab's "bare" page puts table rows straight
# in a <table>, which the HTML parser wraps in a <tbody>, so the server's
# page never matches the view however right the server is. The claim says so
# with a hint at the fix, and repairs the table into the client's shape.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open_page!("hydrate_lab/bare", "#app[data-booted]")?

	Assert.eq(page.evaluate!("String(window.app.hydration().mismatch)")?, "expected <tr> but the server rendered <tbody> (the HTML parser puts a <tr> that sits directly in a <table> inside a <tbody>, so give the rows a tbody of their own)") ? |e| TbodyNotExplained(Str.inspect(e))
	Assert.eq(page.evaluate!("window.labAgainstFresh().then((d) => JSON.stringify(d))")?, "[]") ? |e| RepairedPageDiffersFromAClientBuild(Str.inspect(e))
	assert!(page.find_all("table.rows > tr").has_count(2))?

	browser.close!()?
	Ok({})
}
