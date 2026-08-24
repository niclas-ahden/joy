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
import Effect exposing [Effect]
import Sub exposing [Sub]

Time := [].{

	## Produce a msg once, `ms` milliseconds from now.
	after : U32, (I64 -> msg) -> Effect(msg)
	after = |ms, on_fire| Effect.time_after(ms, on_fire)

	## Produce a msg every `ms` milliseconds, while subscribed.
	every : U32, (I64 -> msg) -> Sub(msg)
	every = |ms, on_tick| Sub.every(ms, on_tick)

	## Produce a msg once, `ms` milliseconds after the LAST `debounce` with
	## this key: issuing the effect again re-arms the pending timer, so only
	## the final call of a burst fires. The classic use is search-as-you-type,
	## where every keystroke returns `Time.debounce("search", 300, ...)` and
	## the query runs 300ms after typing pauses. Keys are global to the app,
	## so pick one per debounced action, and prefix it with the component name
	## when writing reusable components, so two instances cannot swallow each
	## other's timers.
	debounce : Str, U32, (I64 -> msg) -> Effect(msg)
	debounce = |key, ms, on_fire| Effect.time_debounce(key, ms, on_fire)

	## Discard the pending `debounce` timer with this key, so it never
	## fires. No-op when nothing is pending.
	cancel : Str -> Effect(msg)
	cancel = |key| Effect.time_cancel(key)
}

# Each helper is one Effect/Sub constructor call. Pin the variant, the
# parameters, and that the callback survives the wrap.

expect {
	match Time.after(250, |now| "fired:${now.to_str()}") {
		TimeAfter(ms, cb) => {
			inner = Box.unbox(cb)
			ms == 250 and Box.unbox(inner(9)) == "fired:9"
		}
		_ => Bool.False
	}
}

expect {
	match Time.every(16, |now| "tick:${now.to_str()}") {
		Every(r) => {
			inner = Box.unbox(r.on_tick)
			r.ms == 16 and Box.unbox(inner(5)) == "tick:5"
		}
		_ => Bool.False
	}
}

expect {
	match Time.debounce("search", 300, |now| "run:${now.to_str()}") {
		TimeDebounce(key, ms, cb) => {
			inner = Box.unbox(cb)
			key == "search" and ms == 300 and Box.unbox(inner(7)) == "run:7"
		}
		_ => Bool.False
	}
}

expect {
	match Time.cancel("search") {
		TimeCancel(key) => key == "search"
		_ => Bool.False
	}
}
