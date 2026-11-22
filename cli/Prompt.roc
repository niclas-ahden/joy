import pf.Env
import pf.OsStr
import pf.Stdin
import pf.Stdout
import pf.Tty

## Questions for the person at the terminal. A question draws a few lines
## below the cursor, redraws them as keys are pressed, and leaves the answer
## printed. The terminal is in raw mode only while a question is open.
Prompt :: [].{

	## A choice, what it means and a link to read more. The description and
	## the link can be empty.
	Choice : { name : Str, description : Str, link : Str }

	## A line of a list: a choice, or a gap holding the choices left out to
	## keep the list short. Picking a gap opens it in place.
	Item : [One(Prompt.Choice), Gap(Str, List(Prompt.Choice))]

	## Whether to ask at all: never without a terminal, with CI set or with
	## --no-input.
	asks! : Bool => Bool
	asks! = |no_input| {
		in_ci =
			match Env.var_str!(OsStr.from_str("CI")) {
				Ok(value) => value != ""
				Err(_) => False
			}
		!no_input and !in_ci and Tty.is_tty!()
	}

	## A line the person types after a `>` and ends with Enter.
	line! : Str => Try(Str, [Cancelled])
	line! = |question| {
		Stdout.line!("? ${question}") ? |_| Cancelled
		Stdout.write!("> ") ? |_| Cancelled
		answer = Stdin.line!() ? |_| Cancelled
		Ok(answer)
	}

	## Pick one of `choices` with the arrow keys, or j and k, and Enter.
	## Escape and Ctrl-C cancel.
	choose! : Str, List(Prompt.Choice) => Try(Prompt.Choice, _)
	choose! = |question, choices| Prompt.pick!(question, choices.map(|choice| One(choice)))

	## [choose!] from a list that can have gaps in it. A list taller than the
	## terminal scrolls.
	pick! : Str, List(Prompt.Item) => Try(Prompt.Choice, _)
	pick! = |question, given| {
		size = Tty.size!() ?? { width: 80, height: 24 }
		screen = { width: size.width.to_u64(), height: size.height.to_u64(), columns: columns_of(given) }
		Tty.enable_raw_mode!()?
		Stdout.write!("${hide_cursor}? ${question}\r\n")?
		var $state = { items: given, at: 0 }
		var $top = 0
		var $drawn = 0
		var $answer = Err(Cancelled)
		var $asking = True
		first = view($state.items, $state.at, $top, screen)
		Stdout.write!(first.text)?
		$top = first.top
		$drawn = first.count
		while $asking {
			pressed =
				match Stdin.bytes!() {
					Ok(bytes) => key(bytes)
					Err(_) => Cancel
				}
			match step($state, pressed) {
				Asking(next) => {
					$state = next
					drawn = view($state.items, $state.at, $top, screen)
					Stdout.write!("${up($drawn)}${clear_below}${drawn.text}")?
					$top = drawn.top
					$drawn = drawn.count
				}
				Picked(chosen) => {
					$answer = Ok(chosen)
					$asking = False
				}
				Cancelled => {
					$asking = False
				}
			}
		}
		# Leave the question with its answer, and nothing of the list.
		Stdout.write!("${up($drawn + 1)}${clear_below}${show_cursor}")?
		Tty.disable_raw_mode!()?
		match $answer {
			Ok(choice) => Stdout.line!("? ${question} ${choice.name}")?
			Err(_) => Stdout.line!("? ${question} (cancelled)")?
		}
		$answer
	}

	## The lines of a list as [pick!] draws them, for printing where nobody
	## can be asked: every line, as wide as it takes.
	listing : List(Prompt.Item) -> Str
	listing = |items| {
		columns = columns_of(items)
		Str.join_with(items.map(|item| row(item, columns, 0).trim_end()), "\n")
	}
}

## The widths of the name and the description columns, from the choices that
## have more than a name, gaps included, so opening a gap keeps them.
Columns : { name : U64, description : U64 }

columns_of : List(Prompt.Item) -> Columns
columns_of = |items| {
	choices = items.join_map(
		|item|
			match item {
				One(choice) => [choice]
				Gap(_, hidden) => hidden
			},
	)
	wide = choices.keep_if(|choice| !choice.description.is_empty() or !choice.link.is_empty())
	{
		name: wide.map(|choice| choice.name.count_utf8_bytes()).max() ?? 0,
		description: wide.map(|choice| choice.description.count_utf8_bytes()).max() ?? 0,
	}
}

## One line of a list, no wider than `width` when that is above 0. A line
## that would wrap throws the redraw off, so it loses its description first
## and its link last.
row : Prompt.Item, Columns, U64 -> Str
row = |item, columns, width|
	match item {
		Gap(label, _) => "  ${label}"
		One(choice) => {
			name = pad(choice.name, columns.name)
			fits = |line| width == 0 or line.count_utf8_bytes() < width
			full =
				if choice.link.is_empty() {
					"  ${name}  ${choice.description}"
				} else {
					"  ${name}  ${pad(choice.description, columns.description)}  ${choice.link}"
				}
			linked = "  ${name}  ${choice.link}"
			if choice.description.is_empty() and choice.link.is_empty() {
				"  ${choice.name}"
			} else if fits(full) {
				full
			} else if !choice.link.is_empty() and fits(linked) {
				linked
			} else {
				"  ${choice.name}"
			}
		}
	}

pad : Str, U64 -> Str
pad = |text, wanted| {
	have = text.count_utf8_bytes()
	if (have < wanted) "${text}${Str.repeat(" ", wanted - have)}" else text
}

## What is drawn below the question: the items that fit, `at` marked, with
## how many more there are above and below. `top` is the first item shown,
## kept from the last drawing so the list only moves when `at` leaves it.
view : List(Prompt.Item), U64, U64, { width : U64, height : U64, columns : Columns } -> { text : Str, count : U64, top : U64 }
view = |items, at, top, screen| {
	room = if (screen.height > 7) screen.height - 4 else 3
	count = items.len()
	first =
		if count <= room {
			0
		} else if at < top {
			at
		} else if at >= top + room {
			at + 1 - room
		} else if top + room > count {
			count - room
		} else {
			top
		}
	shown = if (count <= room) count else room
	above = if (first > 0) ["  ↑ ${first.to_str()} more"] else []
	below = if (first + shown < count) ["  ↓ ${(count - first - shown).to_str()} more"] else []
	rows =
		items
			.map_with_index(|item, index| (item, index))
			.drop_first(first)
			.take_first(shown)
			.map(
				|(item, index)| {
					line = row(item, screen.columns, screen.width).trim_end()
					if (index == at) "${cyan}>${line.drop_prefix(" ")}${reset}" else line
				},
			)
	lines = above.concat(rows).concat(below)
	{ text: Str.join_with(lines.map(|line| "${clear_line}${line}\r\n"), ""), count: lines.len(), top: first }
}

key : List(U8) -> [Up, Down, Enter, Cancel, Other]
key = |bytes|
	match bytes {
		# The arrow keys arrive as ESC [ A or ESC O A, depending on the terminal.
		[27, 91, 65, ..] | [27, 79, 65, ..] | [107, ..] => Up
		[27, 91, 66, ..] | [27, 79, 66, ..] | [106, ..] => Down
		[13, ..] | [10, ..] => Enter
		[3, ..] | [27] => Cancel
		_ => Other
	}

up : U64 -> Str
up = |count| "\u(1b)[${count.to_str()}A\r"

hide_cursor = "\u(1b)[?25l"

show_cursor = "\u(1b)[?25h"

clear_line = "\u(1b)[2K"

clear_below = "\u(1b)[J"

cyan = "\u(1b)[36m"

reset = "\u(1b)[0m"

expect key([27, 91, 65]) == Up
expect key([106]) == Down
expect key([13]) == Enter
expect key([27]) == Cancel
expect key([27, 91, 67]) == Other

choice = |name, description, link| One({ name, description, link })

expect Prompt.listing([choice("Stay on 0.30.0", "", ""), choice("0.30.4", "Fixes only", "https://a/0.30.4"), Gap("... 2 more", []), choice("0.45.0", "Latest", "https://a/0.45.0")])
	== "  Stay on 0.30.0\n  0.30.4  Fixes only  https://a/0.30.4\n  ... 2 more\n  0.45.0  Latest      https://a/0.45.0"

# Too narrow for the description, then for the link.
expect row(choice("0.30.4", "Fixes only", "https://a/0.30.4"), { name: 6, description: 10 }, 30) == "  0.30.4  https://a/0.30.4"
expect row(choice("0.30.4", "Fixes only", "https://a/0.30.4"), { name: 6, description: 10 }, 20) == "  0.30.4"

expect {
	items = Str.to_utf8("abcdefghijklmnopqrstuvwxyz0123").map(|byte| choice(Str.from_utf8([byte]) ?? "", "", ""))
	drawn = view(items, 25, 0, { width: 80, height: 10, columns: { name: 0, description: 0 } })
	drawn.top == 20 and drawn.count == 8 and drawn.text.contains("↑ 20 more") and drawn.text.contains("↓ 4 more")
}

## Where a list is: its items, with any gap opened so far, and the item
## the cursor is on.
State : { items : List(Prompt.Item), at : U64 }

## What a key does to a list. Enter on a gap opens it in place, with the
## cursor on the first item it held.
step : State, [Up, Down, Enter, Cancel, Other] -> [Asking(State), Picked(Prompt.Choice), Cancelled]
step = |state, pressed| {
	count = state.items.len()
	match pressed {
		Up => Asking({ ..state, at: if (state.at == 0) count - 1 else state.at - 1 })
		Down => Asking({ ..state, at: if (state.at + 1 >= count) 0 else state.at + 1 })
		Enter =>
			match state.items.get(state.at) {
				Ok(One(chosen)) => Picked(chosen)
				Ok(Gap(_, hidden)) => Asking({ ..state, items: state.items.take_first(state.at).concat(hidden.map(|hidden_choice| One(hidden_choice))).concat(state.items.drop_first(state.at + 1)) })
				Err(_) => Cancelled
			}
		Cancel => Cancelled
		Other => Asking(state)
	}
}

## The keys pressed in turn, from the first item.
steps : List(Prompt.Item), List([Up, Down, Enter, Cancel, Other]) -> [Asking(State), Picked(Prompt.Choice), Cancelled]
steps = |items, keys|
	keys.fold(
		Asking({ items, at: 0 }),
		|so_far, pressed|
			match so_far {
				Asking(state) => step(state, pressed)
				done => done
			},
	)

gapped = [choice("Stay", "", ""), choice("0.35.2", "Fixes only", "l"), Gap("... 2 more", [{ name: "0.37.0", description: "", link: "l" }, { name: "0.40.0", description: "", link: "l" }]), choice("0.45.0", "Latest", "l")]

picked_name = |result|
	match result {
		Picked(chosen) => chosen.name
		Asking(_) => "asking"
		Cancelled => "cancelled"
	}

expect picked_name(steps(gapped, [Enter])) == "Stay"
expect picked_name(steps(gapped, [Down, Enter])) == "0.35.2"
# Up from the top wraps to the bottom, and Down from there to the top.
expect picked_name(steps(gapped, [Up, Enter])) == "0.45.0"
expect picked_name(steps(gapped, [Up, Down, Enter])) == "Stay"
# A gap opens in place, the cursor on its first item, and the list grows.
expect picked_name(steps(gapped, [Down, Down, Enter, Enter])) == "0.37.0"
expect picked_name(steps(gapped, [Down, Down, Enter, Down, Enter])) == "0.40.0"
expect picked_name(steps(gapped, [Down, Down, Enter, Down, Down, Enter])) == "0.45.0"
expect picked_name(steps(gapped, [Down, Down, Enter, Up, Up, Up, Enter])) == "0.45.0"
expect picked_name(steps(gapped, [Down, Other, Cancel, Enter])) == "cancelled"
expect picked_name(steps(gapped, [Down])) == "asking"
