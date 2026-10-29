import Reference

## An HTML page from public/ as a build copies it: each `src` and `href` that
## names a file the build renames, joy.js or a file in assets/, given the new
## name, and each bundle root without a `data-joy-wasm` given its wasm. The
## page is read as tags and attributes, so comments, text and the insides of
## `<script>` and `<style>` stay as they are.
HtmlPage :: [].{

	## `html`, the page at `page` below the client folder, with the paths in
	## `renames` (plain to hashed, below the client folder) and the wasm of
	## each bundle id in `wasms`.
	rewrite : Str, Str, Str, List((Str, Str)), List((Str, Str)) -> Str
	rewrite = |html, page, client_url, renames, wasms| {
		bytes = Str.to_utf8(html)
		lower = Str.to_utf8(html.with_ascii_lowercased())
		up = Str.repeat("../", page.split_on("/").len() - 1)
		var $edits = []
		var $i = 0
		while $i < bytes.len() {
			if at(lower, $i, "<!--") {
				$i = after(lower, $i + 4, "-->")
			} else if at(lower, $i, "<!") or at(lower, $i, "</") or at(lower, $i, "<?") {
				$i = after(lower, $i + 2, ">")
			} else if bytes.get($i) == Ok('<') and is_letter(bytes.get($i + 1) ?? 0) {
				tag = read_tag(bytes, lower, $i + 1)
				for attribute in tag.attributes {
					if attribute.name == "src" or attribute.name == "href" {
						raw = text_of(bytes, attribute.value)
						match Reference.resolve(page, raw, client_url) {
							Ok(target) =>
								match renames.find_first(|(plain, _)| plain == target) {
									Ok((_, hashed)) => {
										$edits = $edits.append({ start: attribute.value.start, end: attribute.value.end, text: Reference.renamed(raw, hashed) })
									}
									Err(_) => {}
								}
							Err(_) => {}
						}
					} else if attribute.name == "data-joy-bundle" and !tag.attributes.any(|other| other.name == "data-joy-wasm") {
						id = text_of(bytes, attribute.value)
						match wasms.find_first(|(bundle, _)| bundle == id) {
							Ok((_, wasm)) => {
								$edits = $edits.append({ start: attribute.end, end: attribute.end, text: " data-joy-wasm=\"${up}${wasm}\"" })
							}
							Err(_) => {}
						}
					}
				}
				# A script's or a style's text is not markup.
				$i =
					if tag.closed or !["script", "style"].contains(tag.name) {
						tag.end
					} else {
						until_word(lower, tag.end, "</${tag.name}")
					}
			} else {
				$i = $i + 1
			}
		}
		Reference.apply(bytes, $edits)
	}
}

Span : { start : U64, end : U64 }

Attribute : { name : Str, value : Span, end : U64 }

## A start tag from just past its `<`: its name, its attributes with values,
## where it ends and whether it closed itself with `/>`.
read_tag : List(U8), List(U8), U64 -> { name : Str, attributes : List(Attribute), end : U64, closed : Bool }
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
expect rewritten("<script>const a = '<img src=\"joy.js\">'</script><style>a{b:url(css/site.css)}</style><img src=\"joy.js\">", "index.html") == "<script>const a = '<img src=\"joy.js\">'</script><style>a{b:url(css/site.css)}</style><img src=\"joy.11.js\">"
expect rewritten("<!DOCTYPE html><a href=\"https://example.com/joy.js\">x</a><input disabled value=\"joy.js\"><br/>", "index.html") == "<!DOCTYPE html><a href=\"https://example.com/joy.js\">x</a><input disabled value=\"joy.js\"><br/>"
