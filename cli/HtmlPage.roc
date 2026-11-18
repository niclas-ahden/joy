import Reference
import Stylesheet

## An HTML page from public/ as a build copies it: each path that names a
## file the build renames, joy.js or a file in assets/, given the new name,
## and each bundle root without a `data-joy-wasm` given its wasm. The paths
## are the ones in `src`, `href`, `poster`, `srcset`, `imagesrcset`, a
## `style` attribute, a `<style>` block and the image of a page's `og:` and
## `twitter:` cards. The page is read as tags and attributes, so comments,
## text and the insides of `<script>` stay as they are.
HtmlPage :: [].{

	## `html`, the page at `page` below the client folder, with the paths in
	## `renames` (plain to hashed, below the client folder) and the wasm of
	## each bundle id in `wasms`.
	##
	## A wasm sits beside the loader, so a root names it the way the page's
	## script names joy.js: from the site's root in a page that says
	## `/joy.js`, which a host may answer under any URL of a single-page app,
	## and from the page's own folder in one that says `./joy.js`.
	rewrite : Str, Str, Str, List((Str, Str)), List((Str, Str)) -> Str
	rewrite = |html, page, client_url, renames, wasms| {
		bytes = Str.to_utf8(html)
		tags = start_tags(bytes, Str.to_utf8(html.with_ascii_lowercased()))
		beside = loader_folder(bytes, tags, page, client_url) ?? Str.repeat("../", page.split_on("/").len() - 1)
		rename = |raw| renamed_path(raw, page, client_url, renames)
		var $edits = []
		for tag in tags {
			for attribute in tag.attributes {
				raw = text_of(bytes, attribute.value)
				match kind_of(tag, attribute.name, bytes) {
					OnePath =>
						match rename(raw) {
							Ok(new) => {
								$edits = $edits.append({ start: attribute.value.start, end: attribute.value.end, text: new })
							}
							Err(_) => {}
						}

					Candidates => {
						new = candidates_with(raw, rename)
						if new != raw {
							$edits = $edits.append({ start: attribute.value.start, end: attribute.value.end, text: new })
						}
					}

					Css => {
						new = Stylesheet.rewrite(raw, page, client_url, renames)
						if new != raw {
							$edits = $edits.append({ start: attribute.value.start, end: attribute.value.end, text: new })
						}
					}

					Root =>
						if !tag.attributes.any(|other| other.name == "data-joy-wasm") {
							match wasms.find_first(|(bundle, _)| bundle == raw) {
								Ok((_, wasm)) => {
									$edits = $edits.append({ start: attribute.end, end: attribute.end, text: " data-joy-wasm=\"${beside}${wasm}\"" })
								}
								Err(_) => {}
							}
						}

					Other => {}
				}
			}
			if tag.name == "style" {
				css = text_of(bytes, tag.body)
				new = Stylesheet.rewrite(css, page, client_url, renames)
				if new != css {
					$edits = $edits.append({ start: tag.body.start, end: tag.body.end, text: new })
				}
			}
		}
		Reference.apply(bytes, $edits)
	}

	## The paths in `html` that lead to a file in `renames` and that [rewrite]
	## leaves as written, so they will 404 from a build: in an attribute it
	## does not know, or in a string of a script.
	unrewritten : Str, Str, Str, List((Str, Str)) -> List(Str)
	unrewritten = |html, page, client_url, renames| {
		bytes = Str.to_utf8(html)
		tags = start_tags(bytes, Str.to_utf8(html.with_ascii_lowercased()))
		renamed = |raw| renamed_path(raw, page, client_url, renames).is_ok()
		var $found = []
		for tag in tags {
			for attribute in tag.attributes {
				raw = text_of(bytes, attribute.value)
				if kind_of(tag, attribute.name, bytes) == Other and !attribute.name.starts_with("data-joy-") and renamed(raw) {
					$found = $found.append(raw)
				}
			}
			if tag.name == "script" {
				$found = $found.concat(strings_in(bytes, tag.body).keep_if(renamed))
			}
		}
		$found
	}
}

## How [HtmlPage.rewrite] reads an attribute's value.
kind_of : Tag, Str, List(U8) -> [OnePath, Candidates, Css, Root, Other]
kind_of = |tag, name, bytes|
	if ["src", "href", "poster", "xlink:href"].contains(name) {
		OnePath
	} else if name == "srcset" or name == "imagesrcset" {
		Candidates
	} else if name == "style" {
		Css
	} else if name == "data-joy-bundle" {
		Root
	} else if name == "content" and tag.name == "meta" and tag.attributes.any(|other| (other.name == "property" or other.name == "name") and is_card_image(text_of(bytes, other.value))) {
		OnePath
	} else {
		Other
	}

## Whether a `<meta>` of this property or name holds the image of a page's card.
is_card_image : Str -> Bool
is_card_image = |property| {
	lower = property.with_ascii_lowercased()
	lower.starts_with("og:image") or lower.starts_with("twitter:image")
}

## `raw` with the hashed name, when it leads to a file a build renames.
renamed_path : Str, Str, Str, List((Str, Str)) -> Try(Str, [Kept])
renamed_path = |raw, page, client_url, renames| {
	target = Reference.resolve(page, raw, client_url) ? |_| Kept
	(_, hashed) = renames.find_first(|(plain, _)| plain == target) ? |_| Kept
	Ok(Reference.renamed(raw, hashed))
}

## A `srcset`, with each candidate's path renamed: the candidates are split by
## commas, and each is a path with a width or a density after it.
candidates_with : Str, (Str -> Try(Str, [Kept])) -> Str
candidates_with = |raw, rename|
	Str.join_with(
		raw.split_on(",").map(
			|candidate| {
				trimmed = candidate.trim_start()
				lead = candidate.drop_suffix(trimmed)
				bytes = Str.to_utf8(trimmed)
				path = Str.from_utf8(bytes.take_first(until(bytes, 0, is_space))) ?? trimmed
				match rename(path) {
					Ok(new) => "${lead}${new}${trimmed.drop_prefix(path)}"
					Err(_) => candidate
				}
			},
		),
		",",
	)

## The text of each string in a script.
strings_in : List(U8), Span -> List(Str)
strings_in = |bytes, body| {
	var $found = []
	var $i = body.start
	while $i < body.end {
		quote = bytes.get($i) ?? 0
		if quote == '"' or quote == '\'' or quote == '`' {
			var $j = $i + 1
			while $j < body.end and bytes.get($j) != Ok(quote) {
				$j = if (bytes.get($j) == Ok('\\')) $j + 2 else $j + 1
			}
			end = if ($j < body.end) $j else body.end
			$found = $found.append(text_of(bytes, { start: $i + 1, end }))
			$i = end + 1
		} else {
			$i = $i + 1
		}
	}
	$found
}

Span : { start : U64, end : U64 }

Attribute : { name : Str, value : Span, end : U64 }

## A start tag, and for a script or a style the text up to its end tag.
Tag : { name : Str, attributes : List(Attribute), end : U64, closed : Bool, body : Span }

## Every start tag of a page, in order. A comment is not markup, and neither
## is a script's or a style's text.
start_tags : List(U8), List(U8) -> List(Tag)
start_tags = |bytes, lower| {
	var $tags = []
	var $i = 0
	while $i < bytes.len() {
		if at(lower, $i, "<!--") {
			$i = after(lower, $i + 4, "-->")
		} else if at(lower, $i, "<!") or at(lower, $i, "</") or at(lower, $i, "<?") {
			$i = after(lower, $i + 2, ">")
		} else if bytes.get($i) == Ok('<') and is_letter(bytes.get($i + 1) ?? 0) {
			tag = read_tag(bytes, lower, $i + 1)
			body_end =
				if tag.closed or !["script", "style"].contains(tag.name) {
					tag.end
				} else {
					until_word(lower, tag.end, "</${tag.name}")
				}
			$tags = $tags.append({ ..tag, body: { start: tag.end, end: body_end } })
			$i = body_end
		} else {
			$i = $i + 1
		}
	}
	$tags
}

## The folder the page's script loads joy.js from, as the page writes it: `/`
## for `/joy.js`, `../` for `../joy.js` and nothing for `./joy.js`.
loader_folder : List(U8), List(Tag), Str, Str -> Try(Str, [NoLoader])
loader_folder = |bytes, tags, page, client_url| {
	for tag in tags {
		for attribute in tag.attributes {
			raw = text_of(bytes, attribute.value)
			if tag.name == "script" and attribute.name == "src" and Reference.resolve(page, raw, client_url) == Ok("joy.js") {
				path = Reference.path_of(raw)
				if path.ends_with("joy.js") {
					return Ok(path.drop_suffix("joy.js").drop_prefix("./"))
				}
			}
		}
	}
	Err(NoLoader)
}

## A start tag from just past its `<`: its name, its attributes with values,
## where it ends and whether it closed itself with `/>`.
read_tag : List(U8), List(U8), U64 -> Tag
read_tag = |bytes, lower, from| {
	name_end = until(bytes, from, |byte| is_space(byte) or byte == '>' or byte == '/')
	var $attributes = []
	var $j = name_end
	var $end = None
	while $end == None {
		$j = skip_space(bytes, $j)
		if $j >= bytes.len() {
			$end = Some({ end: bytes.len(), closed: False })
		} else if at(bytes, $j, "/>") {
			$end = Some({ end: $j + 2, closed: True })
		} else if bytes.get($j) == Ok('>') {
			$end = Some({ end: $j + 1, closed: False })
		} else {
			attribute_end = until(bytes, $j, |byte| is_space(byte) or byte == '=' or byte == '>' or byte == '/')
			if attribute_end == $j {
				$j = $j + 1
			} else {
				name = Str.from_utf8(lower.sublist({ start: $j, len: attribute_end - $j })) ?? ""
				equals = skip_space(bytes, attribute_end)
				if bytes.get(equals) == Ok('=') {
					start = skip_space(bytes, equals + 1)
					quote = bytes.get(start) ?? 0
					if quote == '"' or quote == '\'' {
						value_end = until(bytes, start + 1, |byte| byte == quote)
						$attributes = $attributes.append({ name, value: { start: start + 1, end: value_end }, end: value_end + 1 })
						$j = value_end + 1
					} else {
						value_end = until(bytes, start, |byte| is_space(byte) or byte == '>')
						$attributes = $attributes.append({ name, value: { start, end: value_end }, end: value_end })
						$j = value_end
					}
				} else {
					$attributes = $attributes.append({ name, value: { start: attribute_end, end: attribute_end }, end: attribute_end })
					$j = attribute_end
				}
			}
		}
	}
	tag_end =
		match $end {
			Some(found) => found
			None => { end: bytes.len(), closed: False }
		}
	{
		name: Str.from_utf8(lower.sublist({ start: from, len: name_end - from })) ?? "",
		attributes: $attributes,
		end: tag_end.end,
		closed: tag_end.closed,
		body: { start: tag_end.end, end: tag_end.end },
	}
}

text_of : List(U8), Span -> Str
text_of = |bytes, span| Str.from_utf8(bytes.sublist({ start: span.start, len: span.end - span.start })) ?? ""

at : List(U8), U64, Str -> Bool
at = |bytes, i, word| bytes.sublist({ start: i, len: Str.to_utf8(word).len() }) == Str.to_utf8(word)

## The index just past the next `word` from `from`, or the end.
after : List(U8), U64, Str -> U64
after = |bytes, from, word| {
	at_word = until_word(bytes, from, word)
	if (at_word < bytes.len()) at_word + Str.to_utf8(word).len() else bytes.len()
}

## The index of the next `word` from `from`, or the end.
until_word : List(U8), U64, Str -> U64
until_word = |bytes, from, word| {
	var $i = from
	while $i < bytes.len() and !at(bytes, $i, word) {
		$i = $i + 1
	}
	$i
}

until : List(U8), U64, (U8 -> Bool) -> U64
until = |bytes, from, stop| {
	var $i = from
	while $i < bytes.len() and !stop(bytes.get($i) ?? 0) {
		$i = $i + 1
	}
	$i
}

skip_space : List(U8), U64 -> U64
skip_space = |bytes, from| until(bytes, from, |byte| !is_space(byte))

is_space : U8 -> Bool
is_space = |byte| byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r' or byte == 12

is_letter : U8 -> Bool
is_letter = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')

renames = [("joy.js", "joy.11.js"), ("css/site.css", "css/site.22.css")]

wasms = [("catalog", "catalog/app.33.wasm")]

rewritten : Str, Str -> Str
rewritten = |html, page| HtmlPage.rewrite(html, page, "/static/", renames, wasms)

expect rewritten("<script type=\"module\" src=\"./joy.js\"></script>", "index.html") == "<script type=\"module\" src=\"./joy.11.js\"></script>"
expect rewritten("<script src=/static/joy.js?v=2></script><SCRIPT SRC='../joy.js'></SCRIPT>", "docs/page.html") == "<script src=/static/joy.11.js?v=2></script><SCRIPT SRC='../joy.11.js'></SCRIPT>"
expect rewritten("<link rel=stylesheet href=\"css/site.css\"><link href=\"/other/css/site.css\">", "index.html") == "<link rel=stylesheet href=\"css/site.22.css\"><link href=\"/other/css/site.css\">"
expect rewritten("<div data-joy-bundle=\"catalog\" data-joy-flags='{}'></div>", "docs/page.html") == "<div data-joy-bundle=\"catalog\" data-joy-wasm=\"../catalog/app.33.wasm\" data-joy-flags='{}'></div>"
expect rewritten("<div data-joy-wasm=\"mine.wasm\" data-joy-bundle=\"catalog\"></div><div data-joy-bundle=other></div>", "index.html") == "<div data-joy-wasm=\"mine.wasm\" data-joy-bundle=\"catalog\"></div><div data-joy-bundle=other></div>"
expect rewritten("<!-- <script src=\"joy.js\"></script> --><p>src=\"joy.js\" data-joy-bundle=\"catalog\"</p>", "index.html") == "<!-- <script src=\"joy.js\"></script> --><p>src=\"joy.js\" data-joy-bundle=\"catalog\"</p>"
expect rewritten("<script>const a = '<img src=\"joy.js\">'</script><style>a{b:url(css/site.css)}</style><img src=\"joy.js\">", "index.html") == "<script>const a = '<img src=\"joy.js\">'</script><style>a{b:url(css/site.22.css)}</style><img src=\"joy.11.js\">"
expect rewritten("<!DOCTYPE html><a href=\"https://example.com/joy.js\">x</a><input disabled value=\"joy.js\"><br/>", "index.html") == "<!DOCTYPE html><a href=\"https://example.com/joy.js\">x</a><input disabled value=\"joy.js\"><br/>"
expect rewritten("<div data-joy-bundle=\"catalog\"></div><script type=\"module\" src=\"/static/joy.js\"></script>", "index.html") == "<div data-joy-bundle=\"catalog\" data-joy-wasm=\"/static/catalog/app.33.wasm\"></div><script type=\"module\" src=\"/static/joy.11.js\"></script>"
expect rewritten("<div data-joy-bundle=\"catalog\"></div><script type=\"module\" src=\"./joy.js?v=2\"></script>", "index.html") == "<div data-joy-bundle=\"catalog\" data-joy-wasm=\"catalog/app.33.wasm\"></div><script type=\"module\" src=\"./joy.11.js?v=2\"></script>"
expect rewritten("<div data-joy-bundle=\"catalog\"></div><script type=\"module\" src=\"../joy.js\"></script>", "docs/page.html") == "<div data-joy-bundle=\"catalog\" data-joy-wasm=\"../catalog/app.33.wasm\"></div><script type=\"module\" src=\"../joy.11.js\"></script>"
expect rewritten("<img src=\"/static/joy.js\"><div data-joy-bundle=\"catalog\"></div>", "docs/page.html") == "<img src=\"/static/joy.11.js\"><div data-joy-bundle=\"catalog\" data-joy-wasm=\"../catalog/app.33.wasm\"></div>"
expect rewritten("<img srcset=\"css/site.css 1x,\n  /static/css/site.css 2x, other.png 3x\" poster=css/site.css>", "index.html") == "<img srcset=\"css/site.22.css 1x,\n  /static/css/site.22.css 2x, other.png 3x\" poster=css/site.22.css>"
expect rewritten("<meta property=\"og:image\" content=\"/static/css/site.css\"><meta name=description content=\"css/site.css\">", "index.html") == "<meta property=\"og:image\" content=\"/static/css/site.22.css\"><meta name=description content=\"css/site.css\">"
expect rewritten("<p style=\"background: url(css/site.css)\"></p><style>a { b: url('css/site.css') } /* css/site.css */</style>", "index.html") == "<p style=\"background: url(css/site.22.css)\"></p><style>a { b: url('css/site.22.css') } /* css/site.css */</style>"
expect HtmlPage.unrewritten("<img data-src=\"css/site.css\" src=\"css/site.css\"><script>load('/static/css/site.css', \"other.css\")</script><p>css/site.css</p>", "index.html", "/static/", renames) == ["css/site.css", "/static/css/site.css"]
expect HtmlPage.unrewritten("<div data-joy-bundle=\"catalog\" title=\"catalog\"></div><script src=\"joy.js\"></script>", "index.html", "/static/", renames) == []
