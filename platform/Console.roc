## Browser console logging as an effect. The app is pure and the
## compiler enforces it, so logging is data like every other observable
## effect: return `Console.log(...)` in the effect list from `init` or
## `update`. Messages queue host-side and the JS runtime drains the queue to
## `console.log` after each entry call.
##
## There are two console streams. `Console.log` is the intentional app
## logging effect: you own the message, and it lands in `console.log`. The
## `dbg expr` statement is the development printf: it is pure to the effect
## system, so it works anywhere in `init`, `update` or `render`, its output
## format belongs to the compiler (the inspected value), and it lands in
## `console.debug`, which files under the Verbose level in devtools.
## Statement form only, `x = dbg y` is not supported.
import Effect exposing [Effect]

Console := [].{

	## Log a message: the message reaches the console queue when the
	## returned effects run.
	log : Str -> Effect(msg)
	log = |message| Effect.console_log(message)
}
