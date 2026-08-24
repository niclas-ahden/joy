platform ""
	requires {
		[Model : model, Msg : msg] for init : Str -> (Model, List(Effect(Msg))),
		update : Model, Msg -> (Model, List(Effect(Msg))),
		render : Model -> Html(Msg),
		subscriptions : Model -> List(Sub(Msg))
	}
	exposes [Effect, Sub, Http, Time, Keyboard, Console, DOM, Port, WebCrypto]
	packages {
		# The Html/Attribute tree types live in the joy-html package so
		# apps and view packages (e.g. joy-carousel) see the same nominal
		# types as the platform: one tree serves SSR and the client. Apps add
		# this exact URL and `import html.Html`. It must be the same URL, or
		# the app's Html is a different nominal type than the one `render`
		# is required to return.
		html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
	}
	provides {
		"roc_init": init_for_host,
		"roc_update": update_for_host,
		"roc_render": render_for_host,
		"roc_subs": subs_for_host,
		"roc_drop_model": drop_model_for_host,
		"roc_drop_view": drop_view_for_host,
		"roc_drop_cmds": drop_effects_for_host,
		"roc_drop_subs": drop_subs_for_host,
		"roc_drop_http_callback": drop_http_callback_for_host,
		"roc_drop_timer_callback": drop_timer_callback_for_host,
		"roc_drop_key_callback": drop_key_callback_for_host,
		"roc_drop_value_callback": drop_value_callback_for_host,
		"roc_drop_pointer_callback": drop_pointer_callback_for_host,
		"roc_drop_file_callback": drop_file_callback_for_host,
		"roc_drop_bytes_callback": drop_bytes_callback_for_host,
		"roc_drop_str": drop_str_for_host,
		"roc_drop_bytes": drop_bytes_for_host,
	}
	targets: {
		inputs_dir: "targets/",
		wasm32: {
			inputs: ["host.wasm", app],
			# A reactor module: no entry point, the runtime calls in.
			output: Shared,
			# The sole authority for what the module exports. A symbol missing
			# here is stripped from the wasm, however the host declares it.
			exports: [
				"start",
				"dispatch",
				"dispatch_bytes",
				"dispatch_file",
				"dispatch_http",
				"dispatch_key",
				"dispatch_pointer",
				"dispatch_sub",
				"dispatch_sub_key",
				"dispatch_sub_value",
				"dispatch_timer",
				"dispatch_value",
				"drop_timer_cb",
				"cmd_ptr",
				"cmd_len",
				"effects_ptr",
				"effects_len",
				"effects_clear",
				"log_ptr",
				"log_len",
				"log_clear",
				"js_alloc",
				"stack_canary_ok",
				"stack_floor",
				"heap_used",
				"dealloc_miss",
				"lazy_forces",
				"lazy_entries",
				"bench_phase_ms",
			],
		},
	}

import html.Html exposing [Html]
import Effect exposing [Effect]
import Sub exposing [Sub]
import Http
import Time
import Keyboard
import Console
import DOM
import Port
# WebCrypto, not Crypto: the compiler has a builtin `Crypto` module
# (Crypto.SHA256/BLAKE3), and a platform module by the same name shadows it
# with DUPLICATE DEFINITION warnings, which `roc build` treats as exit 2.
import WebCrypto

# The host holds the model as an opaque `Box(Model)` between calls, and every
# event handler and effect callback as an opaque box, so it never needs to
# know the app's concrete Model or Msg types. Effects cross as data (see
# Effect.roc), and `init` receives the app's flags string, into which the
# embedder puts any boot data the app needs, so all four entrypoints are pure.

init_for_host : Str -> (Box(Model), List(Effect(Msg)))
init_for_host = |flags| {
	(model, effects) = init(flags)
	(Box.box(model), effects)
}

update_for_host : Box(Model), Box(Msg) -> (Box(Model), List(Effect(Msg)))
update_for_host = |boxed_model, boxed_msg| {
	(model, effects) = update(Box.unbox(boxed_model), Box.unbox(boxed_msg))
	(Box.box(model), effects)
}

render_for_host : Box(Model) -> Html(Msg)
render_for_host = |boxed| render(Box.unbox(boxed))

subs_for_host : Box(Model) -> List(Sub(Msg))
subs_for_host = |boxed| subscriptions(Box.unbox(boxed))

# Droppers: consuming no-ops the host calls to free values it retained. Each
# takes ownership of its argument and returns nothing, so the compiler
# generates the full recursive decref. This is how the host frees Roc values
# without ever knowing their layouts.

drop_model_for_host : Box(Model) -> {}
drop_model_for_host = |_| {}

drop_view_for_host : Html(Msg) -> {}
drop_view_for_host = |_| {}

# The exported symbol keeps its historical name so the host ABI is stable.
drop_effects_for_host : List(Effect(Msg)) -> {}
drop_effects_for_host = |_| {}

drop_subs_for_host : List(Sub(Msg)) -> {}
drop_subs_for_host = |_| {}

drop_http_callback_for_host : Box(({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> Box(Msg))) -> {}
drop_http_callback_for_host = |_| {}

drop_timer_callback_for_host : Box((I64 -> Box(Msg))) -> {}
drop_timer_callback_for_host = |_| {}

# Also the reason the KeyEvent record (see Sub.KeyEvent) has a layout in the
# generated ABI bindings: the host builds one per key dispatch.
drop_key_callback_for_host : Box(({ key : Str, code : Str, ctrl : Bool, shift : Bool, alt : Bool, meta : Bool, repeat : Bool, is_composing : Bool } -> Box(Msg))) -> {}
drop_key_callback_for_host = |_| {}

# For the boxed `Str -> Box(Msg)` decoders held by port and URL-change
# subscriptions.
drop_value_callback_for_host : Box((Str -> Box(Msg))) -> {}
drop_value_callback_for_host = |_| {}

# Also the reason the PointerEvent record (see Attribute.PointerEvent) has a
# layout in the generated ABI bindings: the host builds one per pointer
# dispatch.
drop_pointer_callback_for_host : Box(({ client_x : F64, client_y : F64, page_x : F64, page_y : F64, offset_x : F64, offset_y : F64, button : U8, buttons : U8, ctrl : Bool, shift : Bool, alt : Bool, meta : Bool } -> Box(Msg))) -> {}
drop_pointer_callback_for_host = |_| {}

# Likewise for the FileInfo record (see Attribute.FileInfo), built by the
# host per file-input dispatch.
drop_file_callback_for_host : Box(({ id : U32, name : Str, mime : Str, size : U64 } -> Box(Msg))) -> {}
drop_file_callback_for_host = |_| {}

# For the boxed `List(U8) -> Box(Msg)` callbacks held by crypto digests.
drop_bytes_callback_for_host : Box((List(U8) -> Box(Msg))) -> {}
drop_bytes_callback_for_host = |_| {}

drop_str_for_host : Str -> {}
drop_str_for_host = |_| {}

drop_bytes_for_host : List(U8) -> {}
drop_bytes_for_host = |_| {}
