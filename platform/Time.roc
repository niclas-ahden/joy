## Time. A one-shot timer as an effect (`after`), a recurring timer as a
## subscription (`every`), and a keyed trailing-edge debounce (`debounce` /
## `cancel`).
##
## There is no clock read: the app is pure and the compiler
## enforces it, so every observable effect is an `Effect` value. Every timer
## firing delivers the current time in its msg, so pure code always has a
## time at hand. An app that needs the clock at boot has the embedder put
## `Date.now()` in the flags string `init` receives (see examples/time.roc).
##
## Each firing calls your function with the current time in ms since the
## Unix epoch and the resulting msg goes to `update`. `every` is a
## subscription: return it from `subscriptions` for as long as it should
## tick, drop it from the list to stop it.
import Effect
import Sub
import Wire

Time := [].{

	## Produce a msg once, `ms` milliseconds from now.
	after : U32, (I64 -> msg) -> Effect(msg)
	after = |ms, on_fire| Effect.call("joy/time/after", Wire.writer({}).u32(ms).done(), |reply| on_fire(now(reply)))

	## Produce a msg every `ms` milliseconds, while subscribed.
	every : U32, (I64 -> msg) -> Sub(msg)
	every = |ms, on_tick| Sub.listen("joy/time/every", Wire.writer({}).u32(ms).done(), |event| on_tick(at(event)))

	## Produce a msg once, `ms` milliseconds after the LAST `debounce` with
	## this key: issuing the effect again re-arms the pending timer, so only
	## the final call of a burst fires. The classic use is search-as-you-type,
	## where every keystroke returns `Time.debounce("search", 300, ...)` and
	## the query runs 300ms after typing pauses. Keys are global to the app,
	## so pick one per debounced action, and prefix it with the component name
	## when writing reusable components, so two instances cannot swallow each
	## other's timers.
	debounce : Str, U32, (I64 -> msg) -> Effect(msg)
	debounce = |key, ms, on_fire| Effect.call("joy/time/debounce", Wire.writer({}).str(key).u32(ms).done(), |reply| on_fire(now(reply)))

	## Discard the pending `debounce` timer with this key, so it never
	## fires. No-op when nothing is pending.
	cancel : Str -> Effect(msg)
	cancel = |key| Effect.send("joy/time/cancel", Wire.writer({}).str(key).done())
}

## The time a timer fired at, in ms since the Unix epoch.
at : List(U8) -> I64
at = |bytes| Wire.reader(bytes).i64().map_ok(|(ms, _)| ms) ?? 0

now : List(U8) -> I64
now = |reply| at(Effect.reply(reply) ?? [])

# Each helper is one operation. Pin the id, the arguments, and that the
# callback survives the wrap.

called : Effect(Str) -> Try({ id : Str, args : List(U8), got : Str }, [NotCalled])
called = |effect|
	match effect {
		Call(id, args, cb) => {
			inner = Box.unbox(cb)
			Ok({ id, args, got: Box.unbox(inner([0].concat(Wire.writer({}).i64(9).done()))) })
		}
		_ => Err(NotCalled)
	}

expect called(Time.after(250, |ms| "fired:${ms.to_str()}")) == Ok({ id: "joy/time/after", args: Wire.writer({}).u32(250).done(), got: "fired:9" })
expect called(Time.debounce("search", 300, |ms| "run:${ms.to_str()}")) == Ok({ id: "joy/time/debounce", args: Wire.writer({}).str("search").u32(300).done(), got: "run:9" })

expect {
	sub = Time.every(16, |ms| "tick:${ms.to_str()}")
	sub.identity() == { id: "joy/time/every", args: Wire.writer({}).u32(16).done() } and sub.deliver(Wire.writer({}).i64(5).done()) == "tick:5"
}

expect {
	match Time.cancel("search") {
		Send(id, args) => id == "joy/time/cancel" and args == Wire.writer({}).str("search").done()
		_ => Bool.False
	}
}
