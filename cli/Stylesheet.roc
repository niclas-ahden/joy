import Reference

## The files a stylesheet in assets/ names, in `url()`, `image-set()` and
## `@import`, and the same stylesheet with those names swapped for hashed
## ones. Comments and other strings are left alone, and function names match
## in any case, as in CSS.
Stylesheet :: [].{

	## The files below the client folder that `css`, the stylesheet at
	## `file` below it, names.
	references : Str, Str, Str -> List(Str)
	references = |css, file, client_url| {
		bytes = Str.to_utf8(css)
		spans(bytes).keep_oks(|span| Reference.resolve(file, text_of(bytes, span), client_url))
	}

	## `css`, the stylesheet at `file`, with each path that leads to a file in
	## `names` changed to lead to its hashed name instead. Anything else, like
	## `data:` or a file outside the client folder, stays as it is.
	rewrite : Str, Str, Str, List((Str, Str)) -> Str
	rewrite = |css, file, client_url, names| {
		bytes = Str.to_utf8(css)
		edits = spans(bytes).keep_oks(
			|span| {
				raw = text_of(bytes, span)
				target = Reference.resolve(file, raw, client_url) ? |_| Unnamed
				(_, hashed) = names.find_first(|(plain, _)| plain == target) ? |_| Unnamed
				Ok({ start: span.start, end: span.end, text: Reference.renamed(raw, hashed) })
			},
		)
		Reference.apply(bytes, edits)
	}
}

Span : { start : U64, end : U64 }

text_of : List(U8), Span -> Str
text_of = |bytes, span| Str.from_utf8(bytes.sublist({ start: span.start, len: span.end - span.start })) ?? ""

## Where each path a stylesheet names starts and ends: the argument of
## `url()`, a string in `image-set()` or `-webkit-image-set()`, and the
## string of `@import`.
spans : List(U8) -> List(Span)
spans = |bytes| {
	var $found = []
	var $i = 0
	# How deep in parentheses the scan is, and the depth of the image-set()
	# it is in, whose strings name files.
	var $depth = 0
	var $image_set = Outside
	while $i < bytes.len() {
		byte = bytes.get($i) ?? 0
		if at(bytes, $i, "/*") {
			$i = after(bytes, $i + 2, "*/")
		} else if byte == '"' or byte == '\'' {
			end = string_end(bytes, $i + 1, byte)
			match $image_set {
				Inside(_) => {
					$found = $found.append({ start: $i + 1, end })
				}
				Outside => {}
			}
			$i = end + 1
		} else if byte == '(' {
			$depth = $depth + 1
			$i = $i + 1
		} else if byte == ')' {
			match $image_set {
				Inside(level) if level == $depth => {
					$image_set = Outside
				}
				_ => {}
			}
			$depth = if ($depth > 0) $depth - 1 else 0
			$i = $i + 1
		} else if byte == '@' {
			name_end = name_end_at(bytes, $i + 1)
			start = skip_space(bytes, name_end)
			quote = bytes.get(start) ?? 0
			if lowered(bytes, $i + 1, name_end) == "import" and (quote == '"' or quote == '\'') {
				end = string_end(bytes, start + 1, quote)
				$found = $found.append({ start: start + 1, end })
				$i = end + 1
			} else {
				$i = name_end
			}
		} else if starts_name(byte) {
			name_end = name_end_at(bytes, $i)
			name = lowered(bytes, $i, name_end)
			if bytes.get(name_end) == Ok('(') {
				$depth = $depth + 1
				if name == "url" {
					start = skip_space(bytes, name_end + 1)
					match bytes.get(start) {
						Ok(quote) if quote == '"' or quote == '\'' => {
							end = string_end(bytes, start + 1, quote)
							$found = $found.append({ start: start + 1, end })
							$i = end + 1
						}
						_ => {
							end = until(bytes, start, |b| b == ')' or is_space(b))
							$found = $found.append({ start, end })
							$i = end
						}
					}
				} else {
					if name == "image-set" or name == "-webkit-image-set" {
						$image_set = Inside($depth)
					}
					$i = name_end + 1
				}
			} else {
				$i = name_end
			}
		} else {
			$i = $i + 1
		}
	}
	$found
}

at : List(U8), U64, Str -> Bool
at = |bytes, i, word| bytes.sublist({ start: i, len: Str.to_utf8(word).len() }) == Str.to_utf8(word)

## The index just past the next `word` from `from`, or the end.
after : List(U8), U64, Str -> U64
after = |bytes, from, word| {
	var $i = from
	while $i < bytes.len() and !at(bytes, $i, word) {
		$i = $i + 1
	}
	if ($i < bytes.len()) $i + Str.to_utf8(word).len() else bytes.len()
}

## The index of the quote that ends a string, past backslash escapes.
string_end : List(U8), U64, U8 -> U64
string_end = |bytes, from, quote| {
	var $i = from
	while $i < bytes.len() and bytes.get($i) != Ok(quote) {
		$i = if (bytes.get($i) == Ok('\\')) $i + 2 else $i + 1
	}
	if ($i < bytes.len()) $i else bytes.len()
}

starts_name : U8 -> Bool
starts_name = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '-' or byte == '_' or byte >= 0x80

name_end_at : List(U8), U64 -> U64
name_end_at = |bytes, from| until(bytes, from, |byte| !(starts_name(byte) or (byte >= '0' and byte <= '9')))

lowered : List(U8), U64, U64 -> Str
lowered = |bytes, start, end| (Str.from_utf8(bytes.sublist({ start, len: end - start })) ?? "").with_ascii_lowercased()

skip_space : List(U8), U64 -> U64
skip_space = |bytes, from| until(bytes, from, |byte| !is_space(byte))

until : List(U8), U64, (U8 -> Bool) -> U64
until = |bytes, from, stop| {
	var $i = from
	while $i < bytes.len() and !stop(bytes.get($i) ?? 0) {
		$i = $i + 1
	}
	$i
}

is_space : U8 -> Bool
is_space = |byte| byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r' or byte == 12

names = [("fonts/a.woff2", "fonts/a.11.woff2"), ("img/b.png", "img/b.22.png"), ("css/base.css", "css/base.33.css")]

rewritten : Str -> Str
rewritten = |css| Stylesheet.rewrite(css, "css/site.css", "/static/", names)

expect rewritten("src: url(\"../fonts/a.woff2\") format(\"woff2\")") == "src: url(\"../fonts/a.11.woff2\") format(\"woff2\")"
expect rewritten("a { background: url( ../img/b.png?v=1#x ) }") == "a { background: url( ../img/b.22.png?v=1#x ) }"
expect rewritten("@import 'base.css';") == "@import 'base.33.css';"
expect rewritten("@IMPORT \"base.css\";") == "@IMPORT \"base.33.css\";"
expect rewritten("@import url(./base.css);") == "@import url(./base.33.css);"
expect rewritten("a{b:URL(../img/b.png)} c{d:Url('../img/b.png')}") == "a{b:URL(../img/b.22.png)} c{d:Url('../img/b.22.png')}"
expect rewritten("a{b:url(/static/img/b.png)} c{d:url(/img/b.png)}") == "a{b:url(/static/img/b.22.png)} c{d:url(/img/b.png)}"
expect rewritten("a{b:image-set(\"../img/b.png\" 1x, url(../img/b.png) 2x)}") == "a{b:image-set(\"../img/b.22.png\" 1x, url(../img/b.22.png) 2x)}"
expect rewritten("a{b:-webkit-image-set('../img/b.png' 1x)} c{d:\"../img/b.png\"}") == "a{b:-webkit-image-set('../img/b.22.png' 1x)} c{d:\"../img/b.png\"}"
expect rewritten("/* url(../img/b.png) */ a{content:\"url(../img/b.png)\"} b{content:\"a\\\"url(../img/b.png)\"}") == "/* url(../img/b.png) */ a{content:\"url(../img/b.png)\"} b{content:\"a\\\"url(../img/b.png)\"}"
expect rewritten("a{b:myurl(../img/b.png)} c{d:url(data:image/png;base64,AA==)} e{f:url(https://x/img/b.png)} g{h:url(missing.png)}") == "a{b:myurl(../img/b.png)} c{d:url(data:image/png;base64,AA==)} e{f:url(https://x/img/b.png)} g{h:url(missing.png)}"
expect rewritten("x{y:url(../../img/b.png)} z{filter:url(\"#blur\")} w{v:url(") == "x{y:url(../../img/b.png)} z{filter:url(\"#blur\")} w{v:url("
expect Stylesheet.rewrite("x{y:url(img/b.png)}", "site.css", "/", names) == "x{y:url(img/b.22.png)}"
expect Stylesheet.references("@import \"base.css\"; a{b:url(../img/b.png)} c{d:url(/x.png)}", "css/site.css", "/static/") == ["css/base.css", "img/b.png"]
