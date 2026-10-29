## A path one file of the client names another by, in a stylesheet's `url()`
## or a page's `src` and `href`, and the edits a build makes to such paths.
Reference :: [].{

	## The file below the client folder that `raw`, written in `file` (itself
	## a path below the client folder), leads to: a relative path from
	## `file`'s folder, or an absolute one below `client_url`. Without its
	## query or fragment. Anything else, like `data:`, another site or a path
	## outside the client folder, is Elsewhere.
	resolve : Str, Str, Str -> Try(Str, [Elsewhere])
	resolve = |file, raw, client_url| {
		path = path_of(raw)
		scheme =
			match path.split_first("/") {
				Ok({ before, .. }) => before.contains(":")
				Err(_) => path.contains(":")
			}
		if path.is_empty() or path.starts_with("//") or scheme {
			return Err(Elsewhere)
		}
		(start, rest) =
			if path.starts_with("/") {
				if !path.starts_with(client_url) {
					return Err(Elsewhere)
				}
				([], path.drop_prefix(client_url))
			} else {
				(file.split_on("/").drop_last(1), path)
			}
		var $parts = start
		for part in rest.split_on("/") {
			if part == ".." {
				if $parts.is_empty() {
					return Err(Elsewhere)
				}
				$parts = $parts.drop_last(1)
			} else if part != "." and part != "" {
				$parts = $parts.append(part)
			}
		}
		Ok(Str.join_with($parts, "/"))
	}

	## `raw` with its file name swapped for the one `hashed` ends in. A hashed
	## file sits in the same folder as its plain one, so the rest of the path
	## still leads there.
	renamed : Str, Str -> Str
	renamed = |raw, hashed| {
		path = path_of(raw)
		rest = raw.drop_prefix(path)
		new_name = last_part(hashed)
		match path.split_last("/") {
			Ok({ before, .. }) => "${before}/${new_name}${rest}"
			Err(_) => "${new_name}${rest}"
		}
	}

	## `bytes` with each edit's range replaced by its text. The edits are in
	## order and do not overlap, and an empty range inserts.
	apply : List(U8), List(Reference.Edit) -> Str
	apply = |bytes, edits| {
		var $out = []
		var $from = 0
		for edit in edits {
			$out = $out.concat(bytes.sublist({ start: $from, len: edit.start - $from })).concat(Str.to_utf8(edit.text))
			$from = edit.end
		}
		Str.from_utf8($out.concat(bytes.drop_first($from))) ?? ""
	}

	Edit : { start : U64, end : U64, text : Str }
}

path_of : Str -> Str
path_of = |raw| {
	before_query =
		match raw.split_first("?") {
			Ok({ before, .. }) => before
			Err(_) => raw
		}
	match before_query.split_first("#") {
		Ok({ before, .. }) => before
		Err(_) => before_query
	}
}

last_part : Str -> Str
last_part = |path|
	match path.split_last("/") {
		Ok({ after, .. }) => after
		Err(_) => path
	}

expect Reference.resolve("css/site.css", "../fonts/a.woff2", "/") == Ok("fonts/a.woff2")
expect Reference.resolve("css/site.css", "../../fonts/a.woff2", "/") == Err(Elsewhere)
expect Reference.resolve("css/site.css", "/static/img/b.png?v=1", "/static/") == Ok("img/b.png")
expect Reference.resolve("css/site.css", "/img/b.png", "/static/") == Err(Elsewhere)
expect Reference.resolve("index.html", "/img/b.png", "/") == Ok("img/b.png")
expect Reference.resolve("index.html", "//cdn.example.com/b.png", "/") == Err(Elsewhere)
expect Reference.resolve("index.html", "data:image/png;base64,AA==", "/") == Err(Elsewhere)
expect Reference.resolve("index.html", "https://example.com/b.png", "/") == Err(Elsewhere)
expect Reference.renamed("../img/b.png?v=1#x", "img/b.22.png") == "../img/b.22.png?v=1#x"
expect Reference.renamed("joy.js", "joy.11.js") == "joy.11.js"
expect Reference.apply(Str.to_utf8("ab cd"), [{ start: 0, end: 2, text: "xy" }, { start: 5, end: 5, text: "!" }]) == "xy cd!"
