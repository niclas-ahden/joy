# Hydration against a real parser: the lab page (tests/apps/hydrate_lab)
# is rendered by joy-html on the server side, parsed by the browser, and
# claimed by the client. Claimed, it must equal a fresh client build of the
# same flags node for node, namespace for namespace, attribute for
# attribute. And whatever the client builds afterwards (SVG shapes,
# keyed icons, MathML) must equal what the parser makes of the same
# markup, and draw. tests/check_svg.mjs and tests/check_hydrate*.mjs own the
# runtime's logic on the fake DOM. This proves the tables and rules match
# the engine's parser, in whichever engine JOY_BROWSER names.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open_page!("hydrate_lab/", "#app[data-booted]")?

	# The claim: clean, and indistinguishable from a client build.
	Assert.eq(page.evaluate!("JSON.stringify(window.app.hydration())")?, "{\"claimed\":true,\"mismatch\":null}") ? |e| ClaimNotClean(Str.inspect(e))
	Assert.eq(page.evaluate!("window.labAgainstFresh().then((d) => JSON.stringify(d))")?, "[]") ? |e| ClaimedPageDiffersFromAClientBuild(Str.inspect(e))

	# A range or color input with no value attribute reads a value the
	# browser made up. Untouched, the app must not hear it as typed ahead.
	Assert.eq(page.evaluate!("document.querySelector('.nudges').textContent")?, "nudges 0") ? |e| UntouchedControlsDeliveredAsTyped(Str.inspect(e))

	# The server's SVG and MathML-free page, as the parser built it.
	Assert.eq(page.evaluate!(namespaces)?, "svg:svg svg:linearGradient svg:use svg:foreignObject xhtml:div svg:desc xhtml:span svg:title") ? |e| ClaimedNamespaces(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.querySelector('.sprite').getAttributeNS('http://www.w3.org/1999/xlink', 'href'))")?, "#dot") ? |e| ClaimedXlinkHref(Str.inspect(e))

	# The values HTML carries differently: a textarea's value as its text, a
	# pre's leading newline (the parser drops one).
	assert!(page.find(".bio").has_value("First line\nsecond line"))?
	Assert.eq(page.evaluate!("JSON.stringify(document.querySelector('.code').textContent)")?, "\"\\nindented()\"") ? |e| PreLostItsNewline(Str.inspect(e))

	# A shape swapped in by the client: SVG, equal to the parser's own, and
	# drawn (an HTML-namespace rect has no box).
	page.click!(".shape")?
	assert!(page.find("rect.shape").is_visible())?
	Assert.eq(page.evaluate!(round_trip(".canvas"))?, "[]") ? |e| SwappedShapeDiffersFromParser(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.querySelector('rect.shape').getBBox().width)")?, "30") ? |e| SwappedShapeNotDrawn(Str.inspect(e))

	# Keyed icons added and rotated: NEW subtrees in SVG, their <use>
	# drawing the symbol.
	page.click!(".add")?
	page.click!(".rotate")?
	assert!(page.find_all(".icon").has_count(3))?
	Assert.eq(page.evaluate!(round_trip(".canvas"))?, "[]") ? |e| NewIconsDifferFromParser(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.querySelector('[data-name=n0] use').getBBox().width > 0)")?, "true") ? |e| NewIconNotDrawn(Str.inspect(e))
	Assert.eq(page.evaluate!("Array.from(document.querySelectorAll('.icon')).map((g) => g.dataset.name).join(',')")?, "b,n0,a") ? |e| IconsNotRotated(Str.inspect(e))

	# MathML swapped in under HTML, with its way back to HTML.
	page.click!(".math")?
	assert!(page.find(".formula").is_visible())?
	Assert.eq(page.evaluate!(round_trip(".formula"))?, "[]") ? |e| FormulaDiffersFromParser(Str.inspect(e))
	Assert.eq(page.evaluate!(math_namespaces)?, "MathML:math xhtml:span MathML:mglyph MathML:mo xhtml:div svg:svg") ? |e| FormulaNamespaces(Str.inspect(e))

	browser.close!()?
	Ok({})
}

## The parser's verdict on a node: the lab page's labRoundTrip, as JSON.
round_trip : Str -> Str
round_trip = |selector| "JSON.stringify(window.labRoundTrip(document.querySelector('${selector}')))"

namespaces : Str
namespaces =
	\\['.canvas', '#grad', '.sprite', 'foreignObject', '.inside-fo', 'desc', '.in-desc', '.icon title']
	\\  .map((s) => document.querySelector(s))
	\\  .map((n) => (n ? n.namespaceURI.split('/').pop() + ':' + n.localName : 'missing'))
	\\  .join(' ')

math_namespaces : Str
math_namespaces =
	\\['.formula', '.in-mi', 'mglyph', 'mo', '.in-annotation', '.svg-in-math']
	\\  .map((s) => document.querySelector(s))
	\\  .map((n) => (n ? n.namespaceURI.split('/').pop() + ':' + n.localName : 'missing'))
	\\  .join(' ')
