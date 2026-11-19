## Timers. Each one hands your app the current time when it fires.
##
## - [Time.after] fires once, after a delay. It is an effect.
## - [Time.every] fires again and again. It is a subscription.
## - [Time.debounce] fires once things have been quiet for a while, and
##   [Time.cancel] calls it off.
##
## A clock that ticks every second:
##
## ```roc
## Msg : [Tick(I64)]
##
## subscriptions = |_model| [Time.every(1000, |now| Tick(now))]
##
## update = |model, msg|
##     match msg {
##         Tick(now) => ({ ..model, now }, [])
##     }
## ```
##
## ## The time you get
##
## Every timer calls your function with the current time, in milliseconds
## since the start of 1970 (the Unix epoch).
##
## There is no function that reads the clock. A timer is how your app learns
## what time it is. If you need the time right at the start, have the page put
## it in the flags, for example `Date.now()` in JavaScript.
##
## The guide has examples to try: [Time](../../#example-time) and
## [Debounce](../../#example-debounce).
import Effect
import Sub
import Wire

Time := [].{

	## Send a message once, `ms` milliseconds from now.
	##
	## ```roc
	## Time.after(3000, |_now| NoticeTimedOut)
	## ```
	after : U32, (I64 -> msg) -> Effect(msg)
	after = |ms, on_fire| Effect.call("joy/time/after", Wire.writer({}).u32(ms).done(), |reply| on_fire(now(reply)))

	## Send a message every `ms` milliseconds, for as long as the subscription is
	## in the list `subscriptions` returns. Leave it out of the list to stop it:
	##
	## ```roc
	## subscriptions = |model|
	##     if model.paused {
	##         []
	##     } else {
	##         [Time.every(1000, |now| Tick(now))]
	##     }
	## ```
	every : U32, (I64 -> msg) -> Sub(msg)
	every = |ms, on_tick| Sub.listen("joy/time/every", Wire.writer({}).u32(ms).done(), |event| on_tick(at(event)))

	## Send a message once, `ms` milliseconds after the last `debounce` with the
	## same key. Each new one starts the wait over, so of a quick run of them only
	## the last fires.
	##
	## Search as you type is the usual case. Every key press asks for the same
	## debounce, and the search runs when the typing has paused:
	##
	## ```roc
	## UserTypedSearch(text) =>
	##     (
	##         { ..model, text },
	##         [Time.debounce("search", 300, |_now| TypingPaused)],
	##     )
	## ```
	##
	## Keys belong to the whole app, so use one per thing you debounce. In a
	## component you mean to reuse, start the key with the component's name.
	debounce : Str, U32, (I64 -> msg) -> Effect(msg)
	debounce = |key, ms, on_fire| Effect.call("joy/time/debounce", Wire.writer({}).str(key).u32(ms).done(), |reply| on_fire(now(reply)))

	## Call off a waiting [Time.debounce] by its key, so it never fires. Does
	## nothing when none is waiting.
	##
	## ```roc
	## Time.cancel("search")
	## ```
	cancel : Str -> Effect(msg)
	cancel = |key| Effect.send("joy/time/cancel", Wire.writer({}).str(key).done())
}

## The time a timer fired at, in ms since the Unix epoch.
at : List(U8) -> I64
at = |bytes| Wire.reader(bytes).i64().map_ok(|(ms, _)| ms) ?? 0

now : List(U8) -> I64
now = |reply| at(Effect.reply(reply) ?? [])

# Each helper is one effect. Pin the id, the arguments, and that the
# callback survives the wrap.

called : Effect(Str) -> Try({ id : Str, args : List(U8), got : Str }, [NotCalled])
called = |effect|
	match effect {
		Call(_, args, cb) => {
			inner = Box.unbox(cb)
			Ok({ id: effect.identity().id, args, got: Box.unbox(inner([0].concat(Wire.writer({}).i64(9).done()))) })
		}
		_ => Err(NotCalled)
	}

expect called(Time.after(250, |ms| "fired:${ms.to_str()}")) == Ok({ id: "joy/time/after", args: Wire.writer({}).u32(250).done(), got: "fired:9" })
expect called(Time.debounce("search", 300, |ms| "run:${ms.to_str()}")) == Ok({ id: "joy/time/debounce", args: Wire.writer({}).str("search").u32(300).done(), got: "run:9" })

expect {
	sub = Time.every(16, |ms| "tick:${ms.to_str()}")
	sub.identity() == { id: "joy/time/every", args: Wire.writer({}).u32(16).done() } and sub.deliver(Wire.writer({}).i64(5).done()) == "tick:5"
}

expect Time.cancel("search").identity() == { id: "joy/time/cancel", args: Wire.writer({}).str("search").done() }
