## Write to the browser's console.
##
## Logging is an effect, like everything else your app does outside itself.
## Return it from `init` or `update`:
##
## ```roc
## update = |model, msg|
##     match msg {
##         UserClickedSave =>
##             (model, [Console.log("Saving ${model.title}")])
##     }
## ```
##
## ## `Console.log` or `dbg`?
##
## - `Console.log` is for lines your app means to write. They show up as
##   ordinary console messages.
## - `dbg` is Roc's own tool for a quick look at a value while you work, like
##   `dbg model.count`. It works anywhere, in `view` too, and needs no effect.
##   Its lines show up at the console's Verbose level, which some browsers
##   hide until you ask for it. Write `dbg` on a line of its own:
##   `x = dbg y` is not supported.
##
## The guide has [a logging example](../../#example-logging) to try.
import Effect

Console := [].{

	## Write a line to the console.
	##
	## ```roc
	## Console.log("The app started")
	## ```
	log : Str -> Effect(msg)
	log = |message| ConsoleLog(message)
}

expect {
	match Console.log("booted") {
		ConsoleLog(message) => message == "booted"
		_ => Bool.False
	}
}
