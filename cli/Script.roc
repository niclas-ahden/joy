## The modules a script in assets/ imports, as written: the string after
## `import` or `from`, and the one `import()` is called with. Comments, strings
## and regular expressions are skipped, so text that only looks like an import
## does not count. Minifiers may write `import()`'s string in backticks. One with
## a `${` in it, or any other expression, names no file.
Script :: [].{

	imported : Str -> List(Str)
	imported = |js| {
		bytes = Str.to_utf8(js)
		var $found = []
		var $i = 0
		var $before = Operator
		var $braces = 0
		# The brace depth of each `${` the scan is inside.
		var $templates = []
		while $i < bytes.len() {
			byte = bytes.get($i) ?? 0
			next = bytes.get($i + 1) ?? 0
			if byte == '/' and next == '/' {
				$i = line_end(bytes, $i)
			} else if byte == '/' and next == '*' {
				$i = comment_end(bytes, $i + 2)
			} else if byte == '/' {
				if $before == Value {
					$i = $i + 1
					$before = Operator
				} else {
					$i = regex_end(bytes, $i + 1) + 1
					$before = Value
				}
			} else if byte == '"' or byte == '\'' {
				$i = string_end(bytes, $i + 1, byte) + 1
				$before = Value
			} else if byte == '`' or (byte == '}' and $templates.last() == Ok($braces)) {
				if byte == '}' {
					$templates = $templates.drop_last(1)
				}
				end = template_end(bytes, $i + 1)
				if bytes.get(end) == Ok('$') {
					$templates = $templates.append($braces)
					$i = end + 2
					$before = Operator
				} else {
					$i = end + 1
					$before = Value
				}
			} else if byte == '{' {
				$braces = $braces + 1
				$i = $i + 1
				$before = Operator
			} else if byte == '}' {
				$braces = if ($braces > 0) $braces - 1 else 0
				$i = $i + 1
				$before = Value
			} else if byte == ')' or byte == ']' {
				$i = $i + 1
				$before = Value
			} else if is_word(byte) {
				end = word_end(bytes, $i)
				word = text_of(bytes, $i, end)
				match if ($before == Dot) Err(NoName) else named_by(bytes, word, end) {
					Ok(start) => {
						quote = bytes.get(start) ?? 0
						name_end = string_end(bytes, start + 1, quote)
						$found = $found.append(text_of(bytes, start + 1, name_end))
						$i = name_end + 1
						$before = Value
					}
					Err(_) => {
						$i = end
						$before = if ($before != Dot and before_regex.contains(word)) Operator else Value
					}
				}
			} else if is_space(byte) {
				$i = $i + 1
			} else {
				$i = $i + 1
				$before = if (byte == '.') Dot else Operator
			}
		}
		$found
	}

	## The imports of `js` that lead to a file by a relative path. Any other
	## name is a package for an import map or a whole URL.
	relative_imported : Str -> List(Str)
	relative_imported = |js| Script.imported(js).keep_if(|name| name.starts_with("./") or name.starts_with("../"))
}

## A regular expression that holds a quote and comes right after `)` or `}` on
## the same line reads as a division and a string, as telling them apart takes a
## full parser. That can miss an import or find one in text, so this scan only
## ever warns.

## Words a `/` after them starts a regular expression instead of dividing.
before_regex : List(Str)
before_regex = ["return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await"]

## Where the string `word` imports starts, at its opening quote.
named_by : List(U8), Str, U64 -> Try(U64, [NoName])
named_by = |bytes, word, end| {
	if word != "import" and word != "from" {
		return Err(NoName)
	}
	after_word = skip_quiet(bytes, end)
	called = word == "import" and bytes.get(after_word) == Ok('(')
	start = if (called) skip_quiet(bytes, after_word + 1) else after_word
	quote = bytes.get(start) ?? 0
	if quote == '"' or quote == '\'' {
		Ok(start)
	} else if called and quote == '`' and bytes.get(template_end(bytes, start + 1)) == Ok('`') {
		Ok(start)
	} else {
		Err(NoName)
	}
}

text_of : List(U8), U64, U64 -> Str
text_of = |bytes, start, end| Str.from_utf8(bytes.sublist({ start, len: end - start })) ?? ""

is_word : U8 -> Bool
is_word = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_' or byte == '$' or byte >= 0x80

word_end : List(U8), U64 -> U64
word_end = |bytes, from| {
	var $i = from
	while $i < bytes.len() and is_word(bytes.get($i) ?? 0) {
		$i = $i + 1
	}
	$i
}

is_space : U8 -> Bool
is_space = |byte| byte == ' ' or byte == '\n' or byte == '\t' or byte == '\r' or byte == 12

## Past any space and comments.
skip_quiet : List(U8), U64 -> U64
skip_quiet = |bytes, from| {
	var $i = from
	var $going = True
	while $going {
		byte = bytes.get($i) ?? 0
		next = bytes.get($i + 1) ?? 0
		if $i < bytes.len() and is_space(byte) {
			$i = $i + 1
		} else if byte == '/' and next == '/' {
			$i = line_end(bytes, $i)
		} else if byte == '/' and next == '*' {
			$i = comment_end(bytes, $i + 2)
		} else {
			$going = False
		}
	}
	$i
}

line_end : List(U8), U64 -> U64
line_end = |bytes, from| {
	var $i = from
	while $i < bytes.len() and bytes.get($i) != Ok('\n') {
		$i = $i + 1
	}
	$i
}

## The index just past the `*/` that closes a comment, or the end.
comment_end : List(U8), U64 -> U64
comment_end = |bytes, from| {
	var $i = from
	while $i < bytes.len() and !(bytes.get($i) == Ok('*') and bytes.get($i + 1) == Ok('/')) {
		$i = $i + 1
	}
	if ($i < bytes.len()) $i + 2 else bytes.len()
}

## The index of the quote that ends a string. A line break ends one that was
## never closed, so a slip in this scan does not swallow the rest of the file.
string_end : List(U8), U64, U8 -> U64
string_end = |bytes, from, quote| {
	var $i = from
	while $i < bytes.len() and bytes.get($i) != Ok(quote) and bytes.get($i) != Ok('\n') {
		$i = if (bytes.get($i) == Ok('\\')) $i + 2 else $i + 1
	}
	if ($i < bytes.len()) $i else bytes.len()
}

## The index of the `/` that ends a regular expression, past escapes and the
## `/` a `[...]` may hold.
regex_end : List(U8), U64 -> U64
regex_end = |bytes, from| {
	var $i = from
	var $in_class = False
	var $going = True
	while $going and $i < bytes.len() {
		byte = bytes.get($i) ?? 0
		if byte == '\\' {
			$i = $i + 2
		} else if byte == '\n' or (byte == '/' and !$in_class) {
			$going = False
		} else {
			if byte == '[' {
				$in_class = True
			} else if byte == ']' {
				$in_class = False
			}
			$i = $i + 1
		}
	}
	if ($i < bytes.len()) $i else bytes.len()
}

## The index of the backtick that ends a template's text, or of the `$` of the
## `${` that interrupts it.
template_end : List(U8), U64 -> U64
template_end = |bytes, from| {
	var $i = from
	var $going = True
	while $going and $i < bytes.len() {
		byte = bytes.get($i) ?? 0
		if byte == '\\' {
			$i = $i + 2
		} else if byte == '`' or (byte == '$' and bytes.get($i + 1) == Ok('{')) {
			$going = False
		} else {
			$i = $i + 1
		}
	}
	if ($i < bytes.len()) $i else bytes.len()
}

expect Script.imported("import a from \"./a.js\";\nimport { b } from './b.js'\nimport './c.js'\n") == ["./a.js", "./b.js", "./c.js"]
expect Script.imported("import*as a from\"./a.js\";import{b}from\"./b.js\";import\"./c.js\";export*from\"./d.js\";export{e}from\"./e.js\"") == ["./a.js", "./b.js", "./c.js", "./d.js", "./e.js"]
expect Script.imported("const a = await import(\"./a.js\"); import ( /* chunk */ './b.js' )") == ["./a.js", "./b.js"]
expect Script.imported("const a = import(`./a.js`).then(b => `import \"./c.js\"`); import ( `./b.js` )") == ["./a.js", "./b.js"]
expect Script.imported("import `./a.js`; from `./b.js`") == []
expect Script.imported("import a from \"./a.json\" with { type: \"json\" }") == ["./a.json"]
expect Script.imported("import /* one */ \"./a.js\" // two") == ["./a.js"]
expect Script.imported("import(name); import(`./\${a}.js`); import.meta.url; x.import(\"./b.js\"); Array.from(\"./c.js\"); x.from \"./d.js\"") == []
expect Script.imported("const from = 1; const important = \"./a.js\"; const y = { from: \"./b.js\" }") == []
expect Script.imported("// import \"./a.js\"\n/* import \"./b.js\" */ /** * import \"./c.js\" **/\nconst s = 'import \"./d.js\"'") == []
expect Script.imported("const s = \"a\\\"import './b.js'\"; import \"./c.js\"") == ["./c.js"]
expect Script.imported("const t = `import \"./a.js\" \${ s } import \"./b.js\"`; import \"./c.js\"") == ["./c.js"]
expect Script.imported("const t = `a\${ { b: `import \"./a.js\"` }.b }import \"./b.js\"`; import \"./c.js\"") == ["./c.js"]
expect Script.imported("const t = `a\${ await import(\"./a.js\") }b`") == ["./a.js"]
expect Script.imported("const r = /[/\"]import \"\\/a.js/; import \"./b.js\"") == ["./b.js"]
expect Script.imported("const q = a / 2; const s = \"x\" / 3; import \"./b.js\"; c = d[0] / 2 / 3") == ["./b.js"]
expect Script.imported("function f() { return /\"/.test(x) }\nimport \"./b.js\"") == ["./b.js"]
expect Script.imported("const s = \"never closed\nimport \"./b.js\"") == ["./b.js"]
expect Script.imported("/* never closed import \"./a.js\"") == []
expect Script.imported("") == []

# Comments
expect Script.imported("/* / import \"./fake.js\" */ import \"./a.js\"") == ["./a.js"]
expect Script.imported("/**/import \"./a.js\"/***/;/* * / */import \"./b.js\"") == ["./a.js", "./b.js"]
expect Script.imported("import // one\n\"./a.js\"") == ["./a.js"]

# What a slash means after each thing that ends a value
expect Script.imported("a={}/2;import\"./a.js\";b=c/3") == ["./a.js"]
expect Script.imported("a=(1)/2;import\"./a.js\";b=c/3") == ["./a.js"]
expect Script.imported("a=b[0]/2;import\"./a.js\";b=c/3") == ["./a.js"]
expect Script.imported("a=x.return/2;import\"./a.js\";b=c/3") == ["./a.js"]
expect Script.imported("a=1/2;import\"./a.js\";b=c/3") == ["./a.js"]

# A regular expression after each word that can come before one
expect Script.imported("return/\"/.test(x);import\"./a.js\"") == ["./a.js"]
expect Script.imported("typeof/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("x instanceof/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("x in/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("for(x of/\"/);import\"./a.js\"") == ["./a.js"]
expect Script.imported("new/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("delete/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("void/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("throw/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("case/\"/:import\"./a.js\"") == ["./a.js"]
expect Script.imported("do/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("else/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("yield/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("await/\"/;import\"./a.js\"") == ["./a.js"]

# Inside a regular expression
expect Script.imported("a=/\\/\"/;import\"./a.js\"") == ["./a.js"]
expect Script.imported("a=/[\\]/\"]/;import\"./a.js\"") == ["./a.js"]

# A slash read as a regular expression stops at the line's end, here after `++`
expect Script.imported("a = b++ / 2\nimport \"./a.js\"\nc = d / 2") == ["./a.js"]

# Templates
expect Script.imported("`\\`b import(\"./fake.js\")`") == []
expect Script.imported("`\\\${ import(\"./fake.js\") }`") == []
expect Script.imported("`\${ { a: 1 }[import(\"./a.js\")] }`") == ["./a.js"]

# Other things called from
expect Script.imported("from(\"./fake.js\"); o = { from(a) { return a } }; class A { from = \"./fake.js\" }") == []
expect Script.imported("import a, { b as from } from \"./a.js\"") == ["./a.js"]

# The limit named above, one miss and one find in text
expect Script.imported("if(x)/\"/.test(y);import\"./a.js\"") == []
expect Script.imported("if(x)/\"/.test(y);z=\"import './fake.js'\";") == ["./fake.js"]

expect Script.relative_imported("import \"./a.js\"; import \"../b.js\"; import \"lit\"; import \"/c.js\"; import \"https://d.e/f.js\"") == ["./a.js", "../b.js"]
