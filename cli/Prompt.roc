import pf.Stdin
import pf.Stdout
import pf.Tty

## Questions for the person at the terminal. A question draws a few lines
## below the cursor, redraws them as keys are pressed, and leaves the answer
## printed. The terminal is in raw mode only while a question is open.
Prompt :: [].{
	Choice : { name : Str, description : Str }

	## Pick one of `choices` with the arrow keys, or j and k, and Enter.
	## Escape and Ctrl-C cancel.
	choose! : Str, List(Prompt.Choice) => Try(Prompt.Choice, _)
	choose! = |question, choices| {
		width = (Tty.size!() ?? { width: 80, height: 24 }).width.to_u64()
		Tty.enable_raw_mode!()?
		Stdout.write!("${hide_cursor}? ${question}\r\n")?
		Stdout.write!(lines(choices, 0, width))?
		var $at = 0
		var $answer = Err(Cancelled)
		var $asking = True
		while $asking {
			pressed =
				match Stdin.bytes!() {
					Ok(bytes) => key(bytes)
					Err(_) => Cancel
				}
			match pressed {
				Up => {
					$at = if ($at == 0) choices.len() - 1 else $at - 1
				}
				Down => {
					$at = if ($at + 1 == choices.len()) 0 else $at + 1
				}
				Enter => {
					$answer = choices.get($at).map_err(|_| Cancelled)
					$asking = False
				}
				Cancel => {
					$asking = False
				}
				Other => {}
			}
			if $asking {
				Stdout.write!("${up(choices.len())}${lines(choices, $at, width)}")?
			}
		}
		# Leave the question with its answer, and nothing of the list.
		Stdout.write!("${up(choices.len() + 1)}${clear_below}${show_cursor}")?
		Tty.disable_raw_mode!()?
		match $answer {
			Ok(choice) => Stdout.line!("? ${question} ${choice.name}")?
			Err(_) => Stdout.line!("? ${question} (cancelled)")?
		}
		$answer
	}
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

## The choices, one per line, with `at` marked. A line wider than the
## terminal would wrap and throw the redraw off, so it loses its description.
lines : List(Prompt.Choice), U64, U64 -> Str
lines = |choices, at, width| {
	longest = choices.map(|choice| choice.name.count_utf8_bytes()).max() ?? 0
	var $out = ""
	for (choice, index) in choices.map_with_index(|choice, index| (choice, index)) {
		name = "${choice.name}${Str.repeat(" ", longest - choice.name.count_utf8_bytes())}"
		full = "  ${name}  ${choice.description}"
		line = if (full.count_utf8_bytes() < width) full else "  ${choice.name}"
		marked = if (index == at) "${cyan}>${line.drop_prefix(" ")}${reset}" else line
		$out = "${$out}${clear_line}${marked}\r\n"
	}
	$out
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
