import html.Html exposing [span, text]
import html.Attribute exposing [class]
import parser.RocSyntax

## Colours for the code blocks. Roc gets its keywords, types, strings,
## numbers, symbols and comments, read with roc-parser's Roc lexer, and
## JavaScript and shell their comments. The classes are the stylesheet's:
## c comment, s string, k keyword, t type, u number and o symbol. The
## stylesheet colours them as an editor colours the same code.
Highlight := [].{
	source : [Roc, Js, Sh, Html, Text], Str -> List(Html(msg))
	source = |lang, src|
		match lang {
			Roc => roc(src)
			Js => comments(src, "//")
			Sh => comments(src, "#")
			Html => [text(src)]
			Text => [text(src)]
		}
}

## Roc source as runs of one class each. The lexer keeps every byte, so the
## runs spell the source exactly and copying the block copies it.
roc : Str -> List(Html(msg))
roc = |src| {
	bytes = src.to_utf8()
	runs = RocSyntax.tokenize_str(src).tokens.fold(
		[],
		|acc, token| {
			cls = class_of(token)
			match acc.last() {
				Ok(last) if last.cls == cls and last.end == token.start => acc.drop_last(1).append({ ..last, end: token.end })
				_ => acc.append({ cls, start: token.start, end: token.end })
			}
		},
	)
	runs.keep_if(|run| run.start < run.end).map(
		|run| {
			piece = text(slice(bytes, run.start, run.end))
			if (run.cls == "") piece else span([class(run.cls)], [piece])
		},
	)
}

## A token's class, or "" for one that stays plain: names and spaces.
class_of : RocSyntax.Token -> Str
class_of = |token|
	match RocSyntax.highlight_category(token.kind) {
		CommentText => "c"
		StringText => "s"
		ReservedWord => "k"
		TypeName => "t"
		NumericLiteral => "u"
		Symbol => "o"
		_ => ""
	}

## Each line's comment coloured, from its marker to the end of the line.
comments : Str, Str -> List(Html(msg))
comments = |src, marker| {
	lines = src.split_on("\n").map(
		|line|
			match line.split_first(marker) {
				Ok({ before, after }) => [text(before), span([class("c")], [text("${marker}${after}")])]
				Err(NotFound) => [text(line)]
			},
	)
	var $out = []
	var $first = Bool.True
	for line in lines {
		$out = if ($first) line else $out.append(text("\n")).concat(line)
		$first = Bool.False
	}
	$out
}

slice : List(U8), U64, U64 -> Str
slice = |bytes, from, to| Str.from_utf8_lossy(bytes.sublist({ start: from, len: to - from }))
