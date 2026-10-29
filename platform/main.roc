platform ""
	requires {
		[Model : model, Msg : msg] for init : Str -> (Model, List(Effect(Msg))),
		update : Model, Msg -> (Model, List(Effect(Msg))),
		view : Model -> Html(Msg),
		subscriptions : Model -> List(Sub(Msg))
	}
	exposes [Effect, Sub, Http, Time, Keyboard, Console, DOM, Clipboard, Port, WebCrypto, Media]
	packages {
		# The Html/Attribute tree types live in the joy-html package so
		# apps and view packages (e.g. joy-carousel) see the same nominal
		# types as the platform: one tree serves SSR and the client. Apps add
		# this exact URL and `import html.Html`. It must be the same URL, or
		# the app's Html is a different nominal type than the one `view`
		# is required to return.
		html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
	}
	provides {
		"roc_init": init_for_host,
		"roc_update": update_for_host,
		"roc_render": view_for_host,
		"roc_subs": subs_for_host,
		"roc_drop_model": drop_model_for_host,
		"roc_drop_view": drop_view_for_host,
		"roc_drop_cmds": drop_effects_for_host,
		"roc_drop_subs": drop_subs_for_host,
		"roc_drop_key_callback": drop_key_callback_for_host,
		"roc_drop_pointer_callback": drop_pointer_callback_for_host,
		"roc_drop_file_callback": drop_file_callback_for_host,
		"roc_drop_bytes_callback": drop_bytes_callback_for_host,
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
				"dispatch_key",
				"dispatch_pointer",
				"dispatch_sub_bytes",
				"drop_call_cb",
				"dispatch_value",
				"cmd_ptr",
				"cmd_len",
				"effects_ptr",
				"effects_len",
				"effects_clear",
				"log_ptr",
				"log_len",
				"log_clear",
				"js_alloc",
				"heap_used",
				"dealloc_miss",
				"lazy_forces",
				"lazy_entries",
				"patch_ops",
				"bench_phase_ms",
			],
		},
	}

import html.Html
import Effect
import Sub
import Http
import Time
import Keyboard
import Console
import DOM
import Clipboard
import Port
# WebCrypto, not Crypto: the compiler has a builtin `Crypto` module
# (Crypto.SHA256/BLAKE3), and a platform module by the same name shadows it
# with DUPLICATE DEFINITION warnings, which `roc build` treats as exit 2.
import WebCrypto
import Media
import Wire

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

view_for_host : Box(Model) -> Html(Msg)
view_for_host = |boxed| view(Box.unbox(boxed))

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

# The reason the KeyEvent record (see Sub.KeyEvent) has a layout in the ABI
# bindings: the host builds one per element key dispatch.
drop_key_callback_for_host : Box(({ key : Str, code : Str, ctrl : Bool, shift : Bool, alt : Bool, meta : Bool, repeat : Bool, is_composing : Bool } -> Box(Msg))) -> {}
drop_key_callback_for_host = |_| {}

# Also the reason the PointerEvent record (see Attribute.PointerEvent) has a
# layout in the generated ABI bindings: the host builds one per pointer
# dispatch.
drop_pointer_callback_for_host : Box(({ client_x : F64, client_y : F64, page_x : F64, page_y : F64, offset_x : F64, offset_y : F64, button : U8, buttons : U8, ctrl : Bool, shift : Bool, alt : Bool, meta : Bool } -> Box(Msg))) -> {}
drop_pointer_callback_for_host = |_| {}

# Likewise for the FileInfo record (see Attribute.FileInfo), built by the
# host per file-input dispatch.
drop_file_callback_for_host : Box(({ id : U32, name : Str, mime : Str, size : U64 } -> Box(Msg))) -> {}
drop_file_callback_for_host = |_| {}

# For the boxed `List(U8) -> Box(Msg)` callbacks of feature calls
# (Effect.call) and events (Sub.listen).
drop_bytes_callback_for_host : Box((List(U8) -> Box(Msg))) -> {}
drop_bytes_callback_for_host = |_| {}

drop_bytes_for_host : List(U8) -> {}
drop_bytes_for_host = |_| {}
