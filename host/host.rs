//! Joy's wasm host, written in Rust, compiled to a single relocatable wasm
//! object that `roc build --target=wasm32` links with the compiled app.
//!
//! The linked module is import-free: it instantiates with an empty import
//! object and is driven purely through exports + linear memory. To stay
//! import-free this host defines every symbol it needs and calls out to
//! nothing: `roc_dbg` queues into the console buffer JS drains (at debug
//! level, next to Console.log's log level), while `roc_expect_failed` and
//! `roc_crashed` stay a no-op and a trap.
//!
//! Memory: a size-class free-list allocator over bump-grown wasm linear
//! memory. Every block is a 16-aligned span holding [capacity word, free-list
//! link][...data], with the data offset chosen per request so `roc_dealloc`
//! (which receives no size) can find the span again: header = max(align, 4)
//! bytes, capacity stored in the span's first word. Freed spans go on
//! per-class free lists (large ones on a first-fit list) and are reused, so
//! sustained update/render cycles stop growing memory once warm. There is no
//! coalescing: fragmentation is bounded by the app's own high-water usage
//! per class, which is fine for an app runtime.
//!
//! Ownership at the boundary is real now: `roc_dealloc` frees, the host
//! increfs what it retains (the model box, handler boxes it re-dispatches,
//! callables the JS side holds), and everything the host wants freed goes
//! through a consuming no-op Roc entry point (`roc_drop_*`), so the compiler
//! generates all recursive freeing and the host never needs type layouts to
//! free them.

#![no_std]
#![allow(static_mut_refs)]

// ABI bindings for platform/main.roc in the shape `roc glue` (Rust spec)
// would emit, committed and hand-maintained because `roc glue` overflows its
// stack on this platform (see build.roc). The file carries size/alignment
// assertions for both pointer widths, the tag discriminants, and the extern
// signatures of every provided entry point. Every offset/stride/discriminant
// constant this host uses is derived from those types (see the aliases
// below), so a platform type change that shifts a layout fails to compile
// instead of silently corrupting the walk.
mod roc_platform_abi;

use core::mem::{offset_of, size_of};
use core::panic::PanicInfo;
use roc_platform_abi as abi;
use roc_platform_abi::RocStr;

const PAGE: usize = 64 * 1024;
// Bump cursor and the current end of grown heap, both in absolute byte offsets
// into linear memory. Lazily initialised on first alloc to the module's current
// memory end, so we never collide with the shadow stack or data below.
static mut NEXT: usize = 0;
static mut END: usize = 0;

// Size classes for freed spans. Spans larger than the last class live on a
// first-fit list. Class values are total span bytes (header + data), always
// multiples of 16 so any 16-aligned span serves any alignment up to 16.
const CLASSES: [usize; 16] = [
    16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096,
];
static mut FREE_HEADS: [usize; 16] = [0; 16];
static mut LARGE_HEAD: usize = 0;

#[inline]
fn align_up(n: usize, align: usize) -> usize {
    let a = if align == 0 { 1 } else { align };
    (n + a - 1) & !(a - 1)
}

/// The bytes between span start and returned data pointer. CONSTANT on
/// purpose: the compiler's generated free paths do not always hand
/// `roc_dealloc` the exact pointer `roc_alloc` returned. Known roc compiler
/// bug: dropping an erased callable stored inside a tag payload passes a
/// pointer 12 bytes too high on wasm32. With a fixed 16-byte header on
/// 16-aligned spans,
/// the true span is recoverable from ANY pointer within 16 bytes above it:
/// align_down(ptr - 16, 16). A magic word in the span header confirms the
/// recovery before anything is freed. 16 also satisfies every alignment Roc
/// uses (the max is the callable capture alignment, 16).
#[inline]
fn header_size(_alignment: usize) -> usize {
    16
}

/// Span header: [capacity u32 @0][free-list next u32 @4][magic u32 @8].
/// The magic ties the capacity to this span so a mis-aimed dealloc can be
/// recognised and recovered (or safely ignored) instead of corrupting a
/// free list.
const SPAN_MAGIC: usize = 0xC0DE_5AFE;

#[inline]
unsafe fn seal_span(span: usize) {
    let capacity = *(span as *const usize);
    *((span + 8) as *mut usize) = capacity ^ SPAN_MAGIC;
}

#[inline]
unsafe fn span_is_sealed(span: usize) -> bool {
    let capacity = *(span as *const usize);
    capacity != 0
        && capacity % 16 == 0
        && *((span + 8) as *const usize) == capacity ^ SPAN_MAGIC
}

/// Recover the span from any pointer the compiler hands `roc_dealloc`. The
/// correct pointer is span+16; buggy paths pass up to 12 bytes higher, and
/// all of those land in the same 16-aligned slot below ptr-ish. Returns 0
/// when no sealed span is found (in which case the caller must not free).
#[inline]
unsafe fn span_of(ptr: usize) -> usize {
    if ptr < 32 {
        return 0;
    }
    let candidate = (ptr - 16) & !15;
    if span_is_sealed(candidate) {
        return candidate;
    }
    0
}

/// The class index whose spans are at least `total` bytes, or None for large.
#[inline]
fn class_of(total: usize) -> Option<usize> {
    let mut i = 0;
    while i < CLASSES.len() {
        if CLASSES[i] >= total {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// Bump a fresh 16-aligned span of `total` bytes off the top of the heap,
/// growing linear memory when out of room. Returns 0 on out-of-memory.
unsafe fn bump_span(total: usize) -> usize {
    if END == 0 {
        let cur = core::arch::wasm32::memory_size(0) * PAGE;
        NEXT = align_up(cur, 16);
        END = cur;
    }
    let start = NEXT;
    let end = start + total;
    if end > END {
        let pages = (end - END + PAGE - 1) / PAGE;
        let prev = core::arch::wasm32::memory_grow(0, pages);
        if prev == usize::MAX {
            return 0;
        }
        END += pages * PAGE; // contiguous: nobody else grows memory
    }
    NEXT = end;
    start
}

/// Take a span of at least `total` bytes: reuse a freed one when a fitting
/// class (or large block) exists, else bump a fresh one. The span's first
/// word is set to its true capacity.
unsafe fn take_span(total: usize) -> usize {
    let span = match class_of(total) {
        Some(class) => {
            let head = FREE_HEADS[class];
            if head != 0 {
                FREE_HEADS[class] = *((head + 4) as *const usize); // next link
                head
            } else {
                let sized = CLASSES[class];
                let s = bump_span(sized);
                if s == 0 {
                    return 0;
                }
                *(s as *mut usize) = sized;
                s
            }
        }
        None => {
            // Large: first fit over the large list.
            let mut prev: usize = 0;
            let mut cur = LARGE_HEAD;
            loop {
                if cur == 0 {
                    let sized = align_up(total, 16);
                    let s = bump_span(sized);
                    if s == 0 {
                        return 0;
                    }
                    *(s as *mut usize) = sized;
                    break s;
                }
                if *(cur as *const usize) >= total {
                    let next = *((cur + 4) as *const usize);
                    if prev == 0 {
                        LARGE_HEAD = next;
                    } else {
                        *((prev + 4) as *mut usize) = next;
                    }
                    break cur;
                }
                prev = cur;
                cur = *((cur + 4) as *const usize);
            }
        }
    };
    if span != 0 {
        seal_span(span);
    }
    span
}

/// Return a span (whose first word holds its capacity) to the free lists.
unsafe fn release_span(span: usize) {
    let total = *(span as *const usize);
    match class_of(total) {
        // A reused class span always has exactly the class size, so freeing
        // into the class that fits WITHIN it keeps reuse symmetric: pick the
        // largest class not exceeding the capacity.
        Some(_) => {
            let mut class = 0;
            let mut i = 0;
            while i < CLASSES.len() {
                if CLASSES[i] <= total {
                    class = i;
                }
                i += 1;
            }
            *((span + 4) as *mut usize) = FREE_HEADS[class];
            FREE_HEADS[class] = span;
        }
        None => {
            *((span + 4) as *mut usize) = LARGE_HEAD;
            LARGE_HEAD = span;
        }
    }
}

/// Allocate `length` bytes aligned to `alignment` (up to 16). The returned
/// pointer sits `max(alignment, 4)` bytes into a 16-aligned span whose first
/// word records the span's capacity, which is how `roc_dealloc` recovers the
/// span without being told the size.
#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut u8 {
    unsafe {
        let header = header_size(alignment);
        let total = align_up(header + length, 16);
        let span = take_span(total);
        if span == 0 {
            return core::ptr::null_mut();
        }
        // The header's spare word records where the REQUESTED bytes end, so
        // `lazy_same` can compare thunk captures without touching class
        // slack. Only meaningful until the span is reallocated in place
        // (which callable allocations never are).
        *((span + 12) as *mut usize) = header + length;
        (span + header) as *mut u8
    }
}

// Diagnostics: deallocs whose pointer recovered no sealed span (each one is
// a silent leak; harnesses can assert this stays zero).
static mut DEALLOC_MISS: u32 = 0;

#[no_mangle]
pub extern "C" fn dealloc_miss() -> u32 {
    unsafe { DEALLOC_MISS }
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut u8, _alignment: usize) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let span = span_of(ptr as usize);
        if span != 0 {
            release_span(span);
        } else {
            // No sealed span found: freeing would corrupt, leaking is safe.
            DEALLOC_MISS += 1;
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_realloc(ptr: *mut u8, new_length: usize, alignment: usize) -> *mut u8 {
    if ptr.is_null() {
        return roc_alloc(new_length, alignment);
    }
    unsafe {
        let span = span_of(ptr as usize);
        if span == 0 {
            // No sealed span means the old size is unknown, so the old
            // contents cannot be copied over. Returning a fresh allocation
            // here would silently lose them. Trap instead.
            core::arch::wasm32::unreachable();
        }
        let capacity = *(span as *const usize);
        let usable = span + capacity - ptr as usize;
        if new_length <= usable {
            return ptr; // grows in place within the span's capacity
        }
        let new_ptr = roc_alloc(new_length, alignment);
        if new_ptr.is_null() {
            return new_ptr;
        }
        // The old usable size caps how much is worth copying; reading the
        // full usable region is safe because it is all inside the old span.
        core::ptr::copy_nonoverlapping(ptr, new_ptr, usable);
        release_span(span);
        new_ptr
    }
}

/// High-water mark of the bump region, in bytes. Once the free lists satisfy
/// steady-state allocation, this stops growing: the memory harness asserts
/// exactly that.
#[no_mangle]
pub extern "C" fn heap_used() -> usize {
    unsafe { NEXT }
}

/// Increment the refcount of a heap value by 1, given its data pointer. The
/// refcount is the isize word directly before the data; 0 marks static data
/// that must not be touched. Single-threaded wasm, so a plain add.
#[inline]
unsafe fn incref(data_ptr: usize) {
    if data_ptr == 0 {
        return;
    }
    let rc = (data_ptr - 4) as *mut isize;
    if *rc != 0 {
        *rc += 1;
    }
}

/// The compiler's `dbg` statement lands here with a UTF-8 rendering of the
/// inspected value. Queue it at debug level, so the runtime drains it to
/// `console.debug` while `Console.log` messages keep going to `console.log`.
#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    unsafe { log_push_copy(bytes, len, LOG_LEVEL_DBG) }
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(_bytes: *const u8, _len: usize) {
    // no-op
}

#[no_mangle]
pub extern "C" fn roc_crashed(_bytes: *const u8, _len: usize) -> ! {
    core::arch::wasm32::unreachable()
}

// --- Boundary types, straight from the generated bindings ---
// The `TypeN` suffixes are glue schema type ids. They shift when the
// platform's type surface changes; these aliases are the only place that
// tracks them, and every layout claim is enforced by the generated
// assertions plus the derived constants below.
type Html = abi::HtmlType50;
type HtmlTag = abi::HtmlType50Tag;
type HtmlElementPayload = abi::HtmlType50ElementPayload;
type Attr = abi::AttributeType52;
type AttrTag = abi::AttributeType52Tag;
type Cmd = abi::CmdType36;
type CmdTag = abi::CmdType36Tag;
type CryptoDigestPayload = abi::CmdType36CryptoDigestPayload;
type CryptoDigestFilePayload = abi::CmdType36CryptoDigestFilePayload;
type HttpSendPayload = abi::CmdType36HttpSendPayload;
type HttpSendFilePayload = abi::CmdType36HttpSendFilePayload;
type PortSendPayload = abi::CmdType36PortSendPayload;
type TimeAfterPayload = abi::CmdType36TimeAfterPayload;
type TimeDebouncePayload = abi::CmdType36TimeDebouncePayload;
/// `Sub(msg)`: Every / Keyboard / PortListen / UrlChanged, each a record payload.
type Sub = abi::SubType9;
type SubTag = abi::SubType9Tag;
/// `Every`'s record `{ ms : U32, on_tick : Box(I64 -> Box(msg)) }` (fields
/// in layout order: the callable first).
type SubEvery = abi::AnonStruct10;
/// `Keyboard`'s record `{ event : Str, keys : List(Str), prevent_default :
/// Bool, on_key : Box(Str -> Box(msg)) }`.
type SubKeyboard = abi::AnonStruct17;
/// `PortListen`'s record `{ name : Str, on_value : Box(Str -> Box(msg)) }`.
type SubPortListen = abi::AnonStruct25;
/// `UrlChanged`'s record `{ on_change : Box(Str -> Box(msg)) }`.
type SubUrlChanged = abi::AnonStruct29;
/// The Http header record `{ name : Str, value : Str }`.
type HeaderPair = abi::AnonStruct38;
/// The HTTP callback's argument record `{ status : U16, headers :
/// List(Header), body : List(U8) }` (fields in layout order: the lists
/// first, body before headers by name).
type HttpArgs = abi::AnonStruct43;
/// The key callbacks' argument record (the platform's `KeyEvent`): two
/// strings and five bools, built per dispatch from what JS passes.
type KeyArgs = abi::AnonStruct22;
/// The pointer callbacks' argument record (the platform's
/// `Attribute.PointerEvent`): six coordinates and six byte-wide fields,
/// built per dispatch from what JS passes.
type PointerArgs = abi::PointerArgs;
/// The file callbacks' argument record (the platform's
/// `Attribute.FileInfo`), built per file-input dispatch.
type FileArgs = abi::FileArgs;

// Bridge-cast safety: `roc_drop_*` take drop-side schema duplicates of the
// live types; the reads only line up if the layouts match. These asserts
// (plus the generated per-type size asserts) turn a bad alias into a compile
// error instead of a corrupt walk.
const _: () = assert!(size_of::<Html>() == size_of::<abi::HtmlType99>());
const _: () = assert!(size_of::<Cmd>() == size_of::<abi::CmdType114>());
const _: () = assert!(size_of::<Sub>() == size_of::<abi::SubType123>());

// The walkers below read host-owned Roc trees through raw offsets rather
// than typed references, so every offset/stride/discriminant they use is
// derived here from the generated types. Nothing in this file states a
// layout number the compiler has not checked.

// `Html(msg)`: Element(Str, List(Attribute), List(Html)) / Text(Str).
const TAG_ELEMENT: u8 = HtmlTag::Element as u8;
const TAG_LAZY: u8 = HtmlTag::Lazy as u8;
const TAG_TEXT: u8 = HtmlTag::Text as u8;
const DISC_OFFSET: usize = offset_of!(Html, tag);
const NODE_STRIDE: usize = size_of::<Html>();
const ATTRS_OFFSET: usize = offset_of!(Html, payload) + offset_of!(HtmlElementPayload, _1);
const CHILDREN_OFFSET: usize = offset_of!(Html, payload) + offset_of!(HtmlElementPayload, _2);

// A `RocList`'s length word, for reading list fields at raw offsets.
const LIST_LEN_OFFSET: usize = offset_of!(abi::RocList<u8>, length);

// `Attribute(msg)`: Boolean(Str, Bool) / Key(Str) /
// KeyHandler(Str, List(Str), Bool, Bool, Box(KeyEvent -> Box(msg))) /
// MsgHandler(Str, Bool, Bool, Box(msg)) /
// PointerHandler(Str, Bool, Bool, Box(PointerEvent -> Box(msg))) /
// PropertyHandler(Str, Str, Bool, Bool, Box(Str -> Box(msg))) /
// String(Str, Str) / VisibilityHandler(Str, Str, Box(msg)).
// Every event handler variant carries the (prevent_default, stop_propagation)
// pair in that order; the layout sorts the box/callable ahead of the bools.
// Field 0 is always the key/name Str; the remaining field offsets are
// per-variant. Keys are diff identity, never a DOM attribute.
const ATTR_STRIDE: usize = size_of::<Attr>();
const ATTR_DISC_OFFSET: usize = offset_of!(Attr, tag);
const ATTR_BOOLEAN: u8 = AttrTag::Boolean as u8;
const ATTR_FILE_HANDLER: u8 = AttrTag::FileHandler as u8;
const ATTR_KEY: u8 = AttrTag::Key as u8;
const ATTR_KEY_HANDLER: u8 = AttrTag::KeyHandler as u8;
const ATTR_MSG_HANDLER: u8 = AttrTag::MsgHandler as u8;
const ATTR_POINTER_HANDLER: u8 = AttrTag::PointerHandler as u8;
const ATTR_PROPERTY_HANDLER: u8 = AttrTag::PropertyHandler as u8;
const ATTR_STRING: u8 = AttrTag::String as u8;
const ATTR_VISIBILITY_HANDLER: u8 = AttrTag::VisibilityHandler as u8;
const ATTR_BOOL_VAL: usize = offset_of!(abi::AttributeType52BooleanPayload, _1);
// The two flags are independent everywhere they appear: prevent_default
// suppresses the browser's own action, stop_propagation stops the event
// reaching ancestor handlers. `on_submit` bakes in prevent_default; the
// `.prevent_default()` / `.stop_propagation()` modifiers set them on any
// handler.
const ATTR_MSG_BOX: usize = offset_of!(abi::AttributeType52MsgHandlerPayload, _1);
const ATTR_MSG_PD: usize = offset_of!(abi::AttributeType52MsgHandlerPayload, _2);
const ATTR_MSG_SP: usize = offset_of!(abi::AttributeType52MsgHandlerPayload, _3);
const ATTR_STR_VAL: usize = offset_of!(abi::AttributeType52StringPayload, _1);
// PropertyHandler's property (_1) names the DOM property the runtime reads
// off the event target ("value", "checked", ...).
const ATTR_PROPERTY_PROP: usize = offset_of!(abi::AttributeType52PropertyHandlerPayload, _1);
const ATTR_PROPERTY_CB: usize = offset_of!(abi::AttributeType52PropertyHandlerPayload, _2);
const ATTR_PROPERTY_PD: usize = offset_of!(abi::AttributeType52PropertyHandlerPayload, _3);
const ATTR_PROPERTY_SP: usize = offset_of!(abi::AttributeType52PropertyHandlerPayload, _4);
const ATTR_KEY_HANDLER_KEYS: usize = offset_of!(abi::AttributeType52KeyHandlerPayload, _1);
const ATTR_KEY_HANDLER_CB: usize = offset_of!(abi::AttributeType52KeyHandlerPayload, _2);
const ATTR_KEY_HANDLER_PD: usize = offset_of!(abi::AttributeType52KeyHandlerPayload, _3);
const ATTR_KEY_HANDLER_SP: usize = offset_of!(abi::AttributeType52KeyHandlerPayload, _4);
// FileHandler's single callable sits at payload offset 0.
const ATTR_POINTER_CB: usize = offset_of!(abi::AttributeType52PointerHandlerPayload, _1);
const ATTR_POINTER_PD: usize = offset_of!(abi::AttributeType52PointerHandlerPayload, _2);
const ATTR_POINTER_SP: usize = offset_of!(abi::AttributeType52PointerHandlerPayload, _3);
const ATTR_VIS_KEY: usize = offset_of!(abi::AttributeType52VisibilityHandlerPayload, _1);
const ATTR_VIS_MSG: usize = offset_of!(abi::AttributeType52VisibilityHandlerPayload, _2);

// --- Command buffer: our own tiny wire protocol (no wasm-bindgen) ---
// The host walks the returned Html tree once and serialises it into a flat u32
// stream. The JS runtime replays it against a node stack to build the DOM,
// batching the wasm↔JS crossing to one per render. Strings are passed by
// (ptr, len) into linear memory, the tree is still alive when JS reads them.
// Build ops (used for a full render and inside a REPLACE subtree):
const OP_ELEMENT_OPEN: u32 = 1; // followed by tag_ptr, tag_len; push new element
const OP_ELEMENT_CLOSE: u32 = 2; // pop current element
const OP_TEXT: u32 = 3; // followed by str_ptr, str_len; append text node
const OP_MSG_EVENT: u32 = 4; // name_ptr, name_len, prevent_default(0/1), stop_propagation(0/1), handler_id (opaque Box(Msg) ptr); bind event on current element
const OP_ATTR: u32 = 7; // key_ptr, key_len, val_ptr, val_len; set a string attribute
const OP_BOOL_ATTR: u32 = 8; // key_ptr, key_len, flag(0/1); set/remove a boolean attribute
const OP_VALUE_EVENT: u32 = 9; // name_ptr, name_len, prop_ptr, prop_len, prevent_default(0/1), stop_propagation(0/1), callable_id (opaque boxed Str->Box(Msg)); bind value event reading the named target property
const OP_KEY_EVENT: u32 = 13; // name_ptr, name_len, prevent_default(0/1), stop_propagation(0/1), callable_id, n_keys, (key_ptr, key_len)*; bind key event (fires with e.key; empty filter matches all)
const OP_VISIBLE: u32 = 11; // margin_ptr, margin_len, key_ptr, key_len, handler_id; observe visibility
const OP_POINTER_EVENT: u32 = 14; // name_ptr, name_len, prevent_default(0/1), stop_propagation(0/1), callable_id; bind pointer event (fires with the PointerEvent record)
const OP_FILE_EVENT: u32 = 15; // callable_id; bind a file input's change event (fires with the FileInfo record)
// Patch ops (used for a diff render). Nodes are addressed by their pre-order
// index in the PREVIOUS tree, which matches the DOM the runtime already built.
const OP_SET_TEXT: u32 = 5; // node_idx, str_ptr, str_len; retarget a text node's value
const OP_REPLACE: u32 = 6; // node_idx, n_words, <build ops...>; swap a subtree for a fresh one
const OP_PATCH_ATTRS: u32 = 10; // node_idx, n_words, <attr ops...>; replace a node's full attribute set
const OP_REORDER: u32 = 12; // parent_idx, old_span, n_children, <descriptors...>; rewrite a child list
const OP_REFRESH_HANDLERS: u32 = 16; // node_idx, n_entries, (name_ptr, name_len, handler_id)*; retarget bound handlers
// OP_REORDER descriptors, one per child of the NEW list, in order. STAY and
// MOVE also carry the old child's pre-order start and subtree size, so the
// runtime can splice its node list instead of re-walking the DOM:
//   STAY old_pos          : the old child at that position, already in place
//   MOVE old_pos          : the old child at that position, to be moved here
//   NEW n_words <build..> : a freshly built subtree
// Old children not referenced by any descriptor are removed. STAY nodes form
// an increasing subsequence (the LIS), so the runtime only touches MOVE/NEW.
const REORDER_STAY: u32 = 0;
const REORDER_MOVE: u32 = 1;
const REORDER_NEW: u32 = 2;

// The first word of every command buffer says how to read the rest.
const MODE_FULL: u32 = 0; // build ops build the whole tree from scratch
const MODE_PATCH: u32 = 1; // patch ops mutate the existing DOM

// The three outbound buffers (commands, effects, console log) are u32-word
// vectors grown on the Roc heap: an overflowing render must never write past
// a fixed static (silent corruption) or drop data (silent loss). Growth
// doubles from the initial capacity; `*_clear`/new renders reuse the
// allocation, so steady state does not realloc. JS re-reads the pointer
// exports on every drain, so a moved buffer is invisible to the runtime.

// Initial capacities, in u32 words. `--cfg small_buffers` shrinks them to a
// few words so the whole test suite exercises the growth path on every
// render (used by build.roc's growth verification pass).
#[cfg(not(small_buffers))]
const CMDS_INITIAL: usize = 4096;
#[cfg(not(small_buffers))]
const EFFECTS_INITIAL: usize = 2048;
#[cfg(not(small_buffers))]
const LOG_INITIAL: usize = 512;
#[cfg(small_buffers)]
const CMDS_INITIAL: usize = 8;
#[cfg(small_buffers)]
const EFFECTS_INITIAL: usize = 8;
#[cfg(small_buffers)]
const LOG_INITIAL: usize = 4;

/// Append `word` to a heap-grown u32 buffer, doubling on demand. Traps on
/// out-of-memory rather than returning: continuing with a partial buffer
/// would corrupt whatever protocol the words encode.
unsafe fn buf_push(ptr: &mut usize, cap: &mut usize, len: &mut usize, initial_cap: usize, word: u32) {
    if *len == *cap {
        let new_cap = if *cap == 0 { initial_cap } else { *cap * 2 };
        let new_ptr = if *ptr == 0 {
            roc_alloc(new_cap * 4, 4) as usize
        } else {
            roc_realloc(*ptr as *mut u8, new_cap * 4, 4) as usize
        };
        if new_ptr == 0 {
            core::arch::wasm32::unreachable();
        }
        *ptr = new_ptr;
        *cap = new_cap;
    }
    *((*ptr + *len * 4) as *mut u32) = word;
    *len += 1;
}

static mut CMDS_PTR: usize = 0;
static mut CMDS_CAP: usize = 0;
static mut CMD_LEN: usize = 0;
// Storage for the current and previous root Html nodes (one node each). The
// host owns the tree ROOT points into, and each diff render moves that
// ownership to PREV_ROOT by copying the 40-byte root before rendering the
// new tree over ROOT. The snapshot's heap data (children, strings) stays
// valid because nothing frees it until `roc_drop_view` consumes the previous
// tree after the diff (see `render_current`).
static mut ROOT: [u8; NODE_STRIDE] = [0; NODE_STRIDE];
static mut PREV_ROOT: [u8; NODE_STRIDE] = [0; NODE_STRIDE];
static mut HAVE_PREV: bool = false;

// Pre-order subtree sizes of the PREVIOUS tree, indexed by pre-order position,
// rebuilt once per diff render (see `build_prev_counts`). `diff_children`
// advances a node index past a child's subtree by an array lookup here instead
// of re-walking that subtree with `count_nodes`, which turns the diff from
// O(n * depth) into O(n). A grow-only host-heap buffer, reused every render so
// steady state does not allocate.
static mut PREV_COUNTS_PTR: usize = 0;
static mut PREV_COUNTS_CAP: usize = 0; // in u32 words (one per node)

// Per-dispatch phase timings in ms, recorded only under `--cfg joy_bench`
// (`JOY_BENCH=1 ./build.roc`). The clock has to come from JS, so an
// instrumented host imports `env.joy_bench_now` and gives up the import-free
// guarantee: benchmark builds only, never a release. The runtime always
// provides the import, and a normal build never declares it. The runtime
// reads the phases through `bench_phase_ms` after each dispatch (0 update,
// 1 render, 2 diff). See tests/bench/.
#[cfg(joy_bench)]
extern "C" {
    fn joy_bench_now() -> f64;
}
#[cfg(joy_bench)]
static mut BENCH_PHASE_MS: [f64; 3] = [0.0; 3];
#[cfg(joy_bench)]
#[no_mangle]
pub extern "C" fn bench_phase_ms(phase: u32) -> f64 {
    // Constant indices so no bounds check (and no panic path) is emitted.
    unsafe {
        match phase {
            0 => BENCH_PHASE_MS[0],
            1 => BENCH_PHASE_MS[1],
            _ => BENCH_PHASE_MS[2],
        }
    }
}

#[inline]
unsafe fn push(word: u32) {
    // Raw-pointer writes throughout: indexing a slice would emit a bounds
    // check that calls `panic_bounds_check`, re-introducing an `env` import
    // and breaking our import-free guarantee.
    buf_push(&mut CMDS_PTR, &mut CMDS_CAP, &mut CMD_LEN, CMDS_INITIAL, word);
}

/// Overwrite an already-pushed command word (used to backpatch a length).
#[inline]
unsafe fn set_word(idx: usize, word: u32) {
    *((CMDS_PTR + idx * 4) as *mut u32) = word;
}

#[inline]
unsafe fn read_u32(off: usize) -> u32 {
    *(off as *const u32)
}

/// `(data_ptr, len)` for the `RocStr` living at linear-memory offset `off`.
/// For a small string the data lives inline in the struct itself, so the
/// returned pointer is `off` and the backing storage must outlive the read.
#[inline]
unsafe fn str_at(off: usize) -> (u32, u32) {
    let s = &*(off as *const RocStr);
    (s.as_u8_ptr() as u32, s.len() as u32)
}

/// Emit the ops for the single attribute at offset `a`. The box/callable
/// pointer doubles as the handler id JS passes back to `dispatch`/
/// `dispatch_value`.
unsafe fn emit_attr(a: usize) {
    match *((a + ATTR_DISC_OFFSET) as *const u8) {
        ATTR_STRING => {
            let (kp, kl) = str_at(a);
            let (vp, vl) = str_at(a + ATTR_STR_VAL);
            push(OP_ATTR);
            push(kp);
            push(kl);
            push(vp);
            push(vl);
        }
        ATTR_BOOLEAN => {
            let (kp, kl) = str_at(a);
            push(OP_BOOL_ATTR);
            push(kp);
            push(kl);
            push(*((a + ATTR_BOOL_VAL) as *const u8) as u32);
        }
        ATTR_MSG_HANDLER => {
            let (np, nl) = str_at(a);
            push(OP_MSG_EVENT);
            push(np);
            push(nl);
            push(*((a + ATTR_MSG_PD) as *const u8) as u32); // prevent_default
            push(*((a + ATTR_MSG_SP) as *const u8) as u32); // stop_propagation
            push(read_u32(a + ATTR_MSG_BOX));
        }
        ATTR_PROPERTY_HANDLER => {
            let (np, nl) = str_at(a);
            let (pp, pl) = str_at(a + ATTR_PROPERTY_PROP);
            push(OP_VALUE_EVENT);
            push(np);
            push(nl);
            push(pp);
            push(pl);
            push(*((a + ATTR_PROPERTY_PD) as *const u8) as u32); // prevent_default
            push(*((a + ATTR_PROPERTY_SP) as *const u8) as u32); // stop_propagation
            push(read_u32(a + ATTR_PROPERTY_CB));
        }
        ATTR_KEY_HANDLER => {
            let (np, nl) = str_at(a);
            push(OP_KEY_EVENT);
            push(np);
            push(nl);
            push(*((a + ATTR_KEY_HANDLER_PD) as *const u8) as u32);
            push(*((a + ATTR_KEY_HANDLER_SP) as *const u8) as u32);
            push(read_u32(a + ATTR_KEY_HANDLER_CB));
            let keys = &*((a + ATTR_KEY_HANDLER_KEYS) as *const abi::RocList<RocStr>);
            push(keys.length as u32);
            for k in 0..keys.length {
                let (kp, kl) = str_at(keys.elements as usize + k * size_of::<RocStr>());
                push(kp);
                push(kl);
            }
        }
        ATTR_POINTER_HANDLER => {
            let (np, nl) = str_at(a);
            push(OP_POINTER_EVENT);
            push(np);
            push(nl);
            push(*((a + ATTR_POINTER_PD) as *const u8) as u32);
            push(*((a + ATTR_POINTER_SP) as *const u8) as u32);
            push(read_u32(a + ATTR_POINTER_CB));
        }
        ATTR_FILE_HANDLER => {
            push(OP_FILE_EVENT);
            push(read_u32(a)); // the callable is the whole payload
        }
        ATTR_VISIBILITY_HANDLER => {
            let (mp, ml) = str_at(a);
            let (kp, kl) = str_at(a + ATTR_VIS_KEY);
            push(OP_VISIBLE);
            push(mp);
            push(ml);
            push(kp);
            push(kl);
            push(read_u32(a + ATTR_VIS_MSG));
        }
        // Key is identity for the differ, never a DOM attribute.
        _ => {}
    }
}

/// Walk the Html node at `off`, appending commands. A `Lazy` node emits
/// its forced subtree, which is what the DOM shows in its place.
unsafe fn emit(off: usize) {
    let off = resolve(off);
    match *((off + DISC_OFFSET) as *const u8) {
        TAG_TEXT => {
            let (ptr, len) = str_at(off);
            push(OP_TEXT);
            push(ptr);
            push(len);
        }
        TAG_ELEMENT => {
            let (ptr, len) = str_at(off); // the tag name, e.g. "div"
            push(OP_ELEMENT_OPEN);
            push(ptr);
            push(len);
            let attrs = read_u32(off + ATTRS_OFFSET) as usize;
            let attrs_count = read_u32(off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
            for i in 0..attrs_count {
                emit_attr(attrs + i * ATTR_STRIDE);
            }
            // children: RocList of inline Html nodes at off+24
            let children = read_u32(off + CHILDREN_OFFSET) as usize;
            let count = read_u32(off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
            for i in 0..count {
                emit(children + i * NODE_STRIDE);
            }
            push(OP_ELEMENT_CLOSE);
        }
        _ => {}
    }
}

// --- Update loop state ---
// The model as an opaque `Box(Model)` pointer, held between calls. The host
// never inspects it. It increfs before lending the box to a Roc entry point
// and drops the old box via `roc_drop_model` when `update` returns a new
// one, so model churn does not grow memory.
static mut MODEL: usize = 0;

// --- Diff ---
// A recursive diff with full child-list reconciliation. Nodes are numbered by
// pre-order DFS over the PREVIOUS tree, which matches the runtime's retained
// `nodeList`, so patches address nodes by that index (node references stay
// valid through moves within a paint). Same kind + same tag → patch in place;
// a kind or tag change REPLACEs the subtree. Child lists are reconciled
// (prefix/suffix sync, then keyed matching with a longest-increasing-
// subsequence pass to minimize moves) and any shape change is emitted as one
// OP_REORDER; matched pairs recurse.

/// Total nodes (self + all descendants) in the subtree at `off`, counting
/// a `Lazy` node as its forced subtree (its DOM footprint), read from the
/// table so retained regions are not re-walked.
unsafe fn count_nodes(off: usize) -> usize {
    if *((off + DISC_OFFSET) as *const u8) == TAG_LAZY {
        return lazy_count(read_u32(off) as usize);
    }
    if *((off + DISC_OFFSET) as *const u8) == TAG_ELEMENT {
        let children = read_u32(off + CHILDREN_OFFSET) as usize;
        let count = read_u32(off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
        let mut n = 1;
        for i in 0..count {
            n += count_nodes(children + i * NODE_STRIDE);
        }
        n
    } else {
        1
    }
}

/// Ensure `PREV_COUNTS` holds at least `n` u32 slots, growing (grow-only) on
/// the host heap. Reused across renders, so it stops reallocating once the
/// app's largest tree has been seen.
unsafe fn ensure_prev_counts(n: usize) {
    if n <= PREV_COUNTS_CAP {
        return;
    }
    let new_cap = if PREV_COUNTS_CAP == 0 {
        if n < 64 { 64 } else { n }
    } else {
        let doubled = PREV_COUNTS_CAP * 2;
        if doubled < n { n } else { doubled }
    };
    let p = if PREV_COUNTS_PTR == 0 {
        roc_alloc(new_cap * 4, 4)
    } else {
        roc_realloc(PREV_COUNTS_PTR as *mut u8, new_cap * 4, 4)
    } as usize;
    if p == 0 {
        core::arch::wasm32::unreachable();
    }
    PREV_COUNTS_PTR = p;
    PREV_COUNTS_CAP = new_cap;
}

/// Fill `PREV_COUNTS[idx..]` with the subtree size of every node in the tree
/// at `off`, numbering nodes in the same pre-order the diff uses (a node's
/// index precedes its children, whose subtrees are contiguous). Returns this
/// subtree's size. One pass, O(nodes).
unsafe fn build_prev_counts(off: usize, idx: usize) -> usize {
    let counts = PREV_COUNTS_PTR as *mut u32;
    // A lazy region occupies [idx, idx + count) in the DOM's pre-order,
    // but a skipped diff never looks inside, so only the region's total is
    // written here. When a changed input makes the diff descend, it fills
    // the inner slots first (see the lazy branches in `diff`).
    if *((off + DISC_OFFSET) as *const u8) == TAG_LAZY {
        let total = lazy_count(read_u32(off) as usize);
        *counts.add(idx) = total as u32;
        return total;
    }
    let total = if *((off + DISC_OFFSET) as *const u8) == TAG_ELEMENT {
        let children = read_u32(off + CHILDREN_OFFSET) as usize;
        let count = read_u32(off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
        let mut n = 1;
        for i in 0..count {
            n += build_prev_counts(children + i * NODE_STRIDE, idx + n);
        }
        n
    } else {
        1
    };
    *counts.add(idx) = total as u32;
    total
}

/// The precomputed subtree size of the previous-tree node at pre-order `idx`.
#[inline]
unsafe fn prev_count(idx: usize) -> usize {
    *((PREV_COUNTS_PTR + idx * 4) as *const u32) as usize
}

// --- Lazy subtrees ---
// A `Lazy` node carries a boxed `{} -> Html` thunk. The host forces it at
// most once per distinct input and retains the forced subtree in a side
// table keyed by the thunk allocation's address, so the DOM's references
// (strings, handler boxes) stay alive across renders that skip the region.
// Two thunks denote the same input when their function pointers match and
// their allocations are byte-identical from the payload on: captures live
// inline in the allocation, hold shared model slices by value, and render
// is pure, so equal bytes mean an equal forced tree. Duplicate keys are
// legal (the same thunk value can sit at several tree positions); rekey
// retargets one entry per call and lookup/mark accept any match.

/// Entry stride in u32 words: [thunk cb, forced node ptr, live mark,
/// forced node count, contained thunk count]. The last two are measured
/// once when the thunk is forced, so steady-state renders read a region's
/// DOM footprint from the table instead of re-walking the subtree.
const LAZY_ENTRY: usize = 5;
static mut LAZY_PTR: usize = 0;
static mut LAZY_LEN: usize = 0;
static mut LAZY_CAP: usize = 0;

// cb -> entry-index hash (open addressing, linear probing). The entries
// array above stays the iteration order for the sweep, while this index makes
// lookup, rekey and mark O(1), so fine-grained lazy scales: a 1000-row list
// with per-row thunks does 1000 of each per render, and the linear scans
// this replaces made that quadratic. Slots are (key, entry_idx) u32 pairs,
// with key 0 = empty and 1 = tombstone (heap pointers are never 0 or 1). A
// duplicate cb occupies its own slot along the probe path. Tombstones come
// from rekey and from sweep removals, and a rebuild purges them when occupied
// + tombstones passes 3/4 of capacity, so probes always terminate at an
// empty slot.
static mut LAZY_IDX_PTR: usize = 0;
static mut LAZY_IDX_CAP: usize = 0; // slots, power of two
static mut LAZY_IDX_USED: usize = 0; // occupied + tombstones
const IDX_EMPTY: u32 = 0;
const IDX_TOMB: u32 = 1;

#[inline]
unsafe fn idx_slot(i: usize) -> *mut u32 {
    (LAZY_IDX_PTR + i * 8) as *mut u32
}

#[inline]
fn idx_hash(cb: usize, cap: usize) -> usize {
    // Thunk allocations are 8-aligned, so drop the dead bits, then spread
    // with the Knuth multiplicative constant.
    ((cb >> 3).wrapping_mul(2654435761)) as usize & (cap - 1)
}

/// Probe insert without growth checks (the rebuild guarantees room).
unsafe fn idx_raw_insert(cb: usize, entry: usize) {
    let mut i = idx_hash(cb, LAZY_IDX_CAP);
    loop {
        let s = idx_slot(i);
        if *s == IDX_EMPTY || *s == IDX_TOMB {
            if *s == IDX_EMPTY {
                LAZY_IDX_USED += 1;
            }
            *s = cb as u32;
            *s.add(1) = entry as u32;
            return;
        }
        i = (i + 1) & (LAZY_IDX_CAP - 1);
    }
}

/// Size (or resize) the slot array to `cap` and reindex every entry,
/// dropping accumulated tombstones.
unsafe fn idx_rebuild(cap: usize) {
    if LAZY_IDX_PTR == 0 {
        LAZY_IDX_PTR = roc_alloc(cap * 8, 4) as usize;
    } else if cap != LAZY_IDX_CAP {
        LAZY_IDX_PTR = roc_realloc(LAZY_IDX_PTR as *mut u8, cap * 8, 4) as usize;
    }
    if LAZY_IDX_PTR == 0 {
        core::arch::wasm32::unreachable();
    }
    LAZY_IDX_CAP = cap;
    LAZY_IDX_USED = 0;
    for i in 0..cap {
        *idx_slot(i) = IDX_EMPTY;
    }
    for e in 0..LAZY_LEN {
        idx_raw_insert(*lazy_entry(e) as usize, e);
    }
}

unsafe fn idx_insert(cb: usize, entry: usize) {
    if LAZY_IDX_CAP == 0 {
        idx_rebuild(64);
    } else if (LAZY_IDX_USED + 1) * 4 >= LAZY_IDX_CAP * 3 {
        // Grow when the live entries themselves need room. Otherwise the
        // load is tombstones, and a same-size rebuild purges them.
        let cap = if (LAZY_LEN + 1) * 2 >= LAZY_IDX_CAP {
            LAZY_IDX_CAP * 2
        } else {
            LAZY_IDX_CAP
        };
        idx_rebuild(cap);
    }
    idx_raw_insert(cb, entry);
}

/// Tombstone the slot mapping `cb` to `entry`.
unsafe fn idx_remove(cb: usize, entry: usize) {
    if LAZY_IDX_CAP == 0 {
        return;
    }
    let mut i = idx_hash(cb, LAZY_IDX_CAP);
    loop {
        let s = idx_slot(i);
        if *s == IDX_EMPTY {
            return;
        }
        if *s == cb as u32 && *s.add(1) as usize == entry {
            *s = IDX_TOMB;
            return;
        }
        i = (i + 1) & (LAZY_IDX_CAP - 1);
    }
}

#[inline]
unsafe fn lazy_entry(i: usize) -> *mut u32 {
    (LAZY_PTR + i * LAZY_ENTRY * 4) as *mut u32
}

unsafe fn lazy_lookup(cb: usize) -> usize {
    let e = lazy_entry_idx(cb);
    if e == LAZY_LEN {
        0
    } else {
        *lazy_entry(e).add(1) as usize
    }
}

unsafe fn lazy_insert(cb: usize, node: usize) {
    if LAZY_LEN == LAZY_CAP {
        let new_cap = if LAZY_CAP == 0 { 8 } else { LAZY_CAP * 2 };
        let p = if LAZY_PTR == 0 {
            roc_alloc(new_cap * LAZY_ENTRY * 4, 4)
        } else {
            roc_realloc(LAZY_PTR as *mut u8, new_cap * LAZY_ENTRY * 4, 4)
        } as usize;
        if p == 0 {
            core::arch::wasm32::unreachable();
        }
        LAZY_PTR = p;
        LAZY_CAP = new_cap;
    }
    let e = lazy_entry(LAZY_LEN);
    *e = cb as u32;
    *e.add(1) = node as u32;
    *e.add(2) = 0;
    *e.add(3) = 0;
    *e.add(4) = 0;
    idx_insert(cb, LAZY_LEN);
    LAZY_LEN += 1;
}

/// Index of the first table entry keyed `cb`, or LAZY_LEN when absent.
unsafe fn lazy_entry_idx(cb: usize) -> usize {
    if LAZY_IDX_CAP == 0 {
        return LAZY_LEN;
    }
    let mut i = idx_hash(cb, LAZY_IDX_CAP);
    loop {
        let s = idx_slot(i);
        if *s == IDX_EMPTY {
            return LAZY_LEN;
        }
        if *s == cb as u32 {
            return *s.add(1) as usize;
        }
        i = (i + 1) & (LAZY_IDX_CAP - 1);
    }
}

/// The DOM footprint (total node count) of the forced subtree for the
/// thunk at `cb`, forcing and measuring it on first sight.
unsafe fn lazy_count(cb: usize) -> usize {
    lazy_force(cb);
    *lazy_entry(lazy_entry_idx(cb)).add(3) as usize
}

/// Node count and direct-thunk count of the subtree at `off`. A `Lazy`
/// node contributes its region's measured footprint and counts as one
/// contained thunk without being walked into: whoever reaches it later
/// consults its own table entry.
unsafe fn measure(off: usize) -> (usize, usize) {
    match *((off + DISC_OFFSET) as *const u8) {
        TAG_LAZY => (lazy_count(read_u32(off) as usize), 1),
        TAG_ELEMENT => {
            let children = read_u32(off + CHILDREN_OFFSET) as usize;
            let count = read_u32(off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
            let mut nodes = 1;
            let mut thunks = 0;
            for i in 0..count {
                let (n, t) = measure(children + i * NODE_STRIDE);
                nodes += n;
                thunks += t;
            }
            (nodes, thunks)
        }
        _ => (1, 0),
    }
}

/// Move the retained subtree of the entry keyed `old_cb` under `new_cb`
/// (a hit: the new thunk denotes the same input). No-op when no entry is
/// left under `old_cb` (the same shared thunk was already rekeyed at an
/// earlier tree position).
unsafe fn lazy_rekey(old_cb: usize, new_cb: usize) {
    let e = lazy_entry_idx(old_cb);
    if e >= LAZY_LEN {
        return;
    }
    idx_remove(old_cb, e);
    *lazy_entry(e) = new_cb as u32;
    // Same growth policy as idx_insert, but a rebuild reads the entries
    // array, which already holds new_cb, so it indexes the rewritten entry
    // itself. Only the non-rebuild path may insert, or the mapping would be
    // doubled.
    if LAZY_IDX_CAP == 0 {
        idx_rebuild(64);
    } else if (LAZY_IDX_USED + 1) * 4 >= LAZY_IDX_CAP * 3 {
        let cap = if (LAZY_LEN + 1) * 2 >= LAZY_IDX_CAP {
            LAZY_IDX_CAP * 2
        } else {
            LAZY_IDX_CAP
        };
        idx_rebuild(cap);
    } else {
        idx_raw_insert(new_cb, e);
    }
}

/// The forced subtree for the thunk at `cb`, forcing and retaining it on
/// first sight. The forced root is an owned (+1) Html value in its own
/// stable allocation, dropped only when `lazy_sweep` finds the thunk gone
/// from the retained tree.
unsafe fn lazy_force(cb: usize) -> usize {
    let hit = lazy_lookup(cb);
    if hit != 0 {
        return hit;
    }
    let buf = roc_alloc(NODE_STRIDE, 8) as usize;
    if buf == 0 {
        core::arch::wasm32::unreachable();
    }
    let payload = &*(cb as *const abi::RocErasedCallablePayload);
    let unit: u8 = 0;
    (payload.callable_fn_ptr)(
        core::ptr::null_mut(),
        buf as *mut u8,
        &raw const unit,
        (cb + abi::ROC_ERASED_CALLABLE_CAPTURE_OFFSET) as *mut u8,
        core::ptr::null_mut(), // no allocation handed over for reuse
    );
    let my = LAZY_LEN;
    lazy_insert(cb, buf);
    // Measure once, now. Nested thunks force (and measure) during this
    // walk, appending entries, which leaves this entry's index valid.
    let (nodes, thunks) = measure(buf);
    let e = lazy_entry(my);
    *e.add(3) = nodes as u32;
    *e.add(4) = thunks as u32;
    buf
}

/// The node at `off`, with a `Lazy` node standing in for its forced
/// subtree (which is what the DOM actually shows).
#[inline]
unsafe fn resolve(off: usize) -> usize {
    if *((off + DISC_OFFSET) as *const u8) == TAG_LAZY {
        lazy_force(read_u32(off) as usize)
    } else {
        off
    }
}

/// Do two thunks denote the same input? Same function pointer and
/// byte-identical capture records. Captures live inline at a fixed offset
/// in the thunk allocation, whose span header records where the requested
/// bytes end (see `roc_alloc`), so the comparison covers exactly the
/// captures: no header padding, no class slack. Captures hold shared
/// model slices by value, so equal bytes plus a pure render mean equal
/// forced trees. Static thunk allocations carry no span header and fall
/// out as a miss unless they are the same address.
unsafe fn lazy_same(a: usize, b: usize) -> bool {
    if a == b {
        return true;
    }
    let pa = &*(a as *const abi::RocErasedCallablePayload);
    let pb = &*(b as *const abi::RocErasedCallablePayload);
    if pa.callable_fn_ptr as usize != pb.callable_fn_ptr as usize {
        return false;
    }
    let (sa, sb) = (a.wrapping_sub(32), b.wrapping_sub(32));
    if !span_is_sealed(sa) || !span_is_sealed(sb) {
        return false;
    }
    let cap_a = a + abi::ROC_ERASED_CALLABLE_CAPTURE_OFFSET;
    let cap_b = b + abi::ROC_ERASED_CALLABLE_CAPTURE_OFFSET;
    let end_a = sa + *((sa + 12) as *const usize);
    let end_b = sb + *((sb + 12) as *const usize);
    if end_a < cap_a || end_b < cap_b || end_a - cap_a != end_b - cap_b {
        return false;
    }
    let len = (end_a - cap_a) as u32;
    bytes_eq(cap_a as u32, len, cap_b as u32, len)
}

/// Mark every entry whose thunk is reachable from the retained tree at
/// `off`, descending through forced content (which may nest lazies).
/// Duplicate-keyed entries hold byte-equal content, so descending through
/// the first match covers the nested thunks of all of them.
unsafe fn lazy_mark_live(off: usize) {
    match *((off + DISC_OFFSET) as *const u8) {
        TAG_LAZY => {
            // Mark every entry keyed `cb` (duplicates share one probe path).
            let cb = read_u32(off);
            let mut content = 0usize;
            let mut thunks = 0u32;
            if LAZY_IDX_CAP != 0 {
                let mut i = idx_hash(cb as usize, LAZY_IDX_CAP);
                loop {
                    let s = idx_slot(i);
                    if *s == IDX_EMPTY {
                        break;
                    }
                    if *s == cb {
                        let e = lazy_entry(*s.add(1) as usize);
                        *e.add(2) = 1;
                        if content == 0 {
                            content = *e.add(1) as usize;
                            thunks = *e.add(4);
                        }
                    }
                    i = (i + 1) & (LAZY_IDX_CAP - 1);
                }
            }
            // Descending only finds nested thunks. A region measured
            // thunk-free at force time has none to find, so the walk stops
            // at its boundary, keeping the sweep O(header) per render no
            // matter how big the retained content is.
            if content != 0 && thunks != 0 {
                lazy_mark_live(content);
            }
        }
        TAG_ELEMENT => {
            let children = read_u32(off + CHILDREN_OFFSET) as usize;
            let count = read_u32(off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
            for i in 0..count {
                lazy_mark_live(children + i * NODE_STRIDE);
            }
        }
        _ => {}
    }
}

/// Drop retained subtrees whose thunks are no longer in the retained tree.
/// Runs after the previous tree has been dropped and before anything else
/// allocates, so stale keys cannot alias a reused address. The dropped
/// content may be referenced by the DOM until the pending patch paints,
/// which is safe for the same reason dropping the previous tree is: every
/// handler-carrying element re-emits its handler ids on any non-skipped
/// diff (a full attribute patch or an OP_REFRESH_HANDLERS), so JS refreshes
/// those references before the next dispatch.
unsafe fn lazy_sweep() {
    for i in 0..LAZY_LEN {
        *lazy_entry(i).add(2) = 0;
    }
    lazy_mark_live(&raw const ROOT as usize);
    let mut removed = false;
    let mut i = 0;
    while i < LAZY_LEN {
        let e = lazy_entry(i);
        if *e.add(2) == 0 {
            let node = *e.add(1) as usize;
            abi::roc_drop_view(*(node as *const abi::HtmlType99));
            roc_dealloc(node as *mut u8, 8);
            let last = lazy_entry(LAZY_LEN - 1);
            *e = *last;
            *e.add(1) = *last.add(1);
            *e.add(2) = *last.add(2);
            *e.add(3) = *last.add(3);
            *e.add(4) = *last.add(4);
            LAZY_LEN -= 1;
            removed = true;
        } else {
            i += 1;
        }
    }
    // The swap-removals above moved entries, so their index rows are stale.
    // One rebuild fixes them all (and purges tombstones). Steady-state
    // renders remove nothing and skip this.
    if removed && LAZY_IDX_CAP != 0 {
        idx_rebuild(LAZY_IDX_CAP);
    }
}

/// Are the attributes at offsets `a` and `b` identical, such that the runtime
/// needs no update? Handlers land in the catch-all arm: their boxed messages
/// are freshly allocated every render, so they are never identical. But see
/// `attrs_delta`, which recognises when the box id is the ONLY difference.
unsafe fn attr_eq(a: usize, b: usize) -> bool {
    let disc = *((a + ATTR_DISC_OFFSET) as *const u8);
    if disc != *((b + ATTR_DISC_OFFSET) as *const u8) {
        return false;
    }
    match disc {
        ATTR_STRING => str_eq(a, b) && str_eq(a + ATTR_STR_VAL, b + ATTR_STR_VAL),
        ATTR_BOOLEAN => {
            str_eq(a, b) && *((a + ATTR_BOOL_VAL) as *const u8) == *((b + ATTR_BOOL_VAL) as *const u8)
        }
        ATTR_KEY => str_eq(a, b),
        _ => false,
    }
}

// Outcome of comparing two elements' attribute lists for the patch decision.
const ATTRS_SAME: u32 = 0; // nothing to emit
const ATTRS_REFRESH: u32 = 1; // only the handler boxes changed: refresh their ids
const ATTRS_CHANGED: u32 = 2; // anything else: full attribute patch

/// Classify the difference between two elements' attribute lists. Handler
/// boxes are freshly allocated every render, so comparing them is pointless.
/// What matters is whether everything AROUND the boxes (names, flags, value
/// props, key filters, string/bool attrs) is unchanged. Then the runtime
/// only needs the new box ids (`OP_REFRESH_HANDLERS`), which skips the full
/// attribute rewrite that would otherwise run for every handler-carrying
/// element on every diff. File and visibility handlers stay on the full-patch
/// path: they are rare, and their setup (input wiring, observers) lives in
/// the runtime's attribute code.
unsafe fn attrs_delta(old_off: usize, new_off: usize) -> u32 {
    let old_count = read_u32(old_off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
    let new_count = read_u32(new_off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
    if old_count != new_count {
        return ATTRS_CHANGED;
    }
    let old_attrs = read_u32(old_off + ATTRS_OFFSET) as usize;
    let new_attrs = read_u32(new_off + ATTRS_OFFSET) as usize;
    let mut handlers = false;
    for i in 0..new_count {
        let a = old_attrs + i * ATTR_STRIDE;
        let b = new_attrs + i * ATTR_STRIDE;
        let disc = *((a + ATTR_DISC_OFFSET) as *const u8);
        if disc != *((b + ATTR_DISC_OFFSET) as *const u8) {
            return ATTRS_CHANGED;
        }
        match disc {
            ATTR_STRING | ATTR_BOOLEAN | ATTR_KEY => {
                if !attr_eq(a, b) {
                    return ATTRS_CHANGED;
                }
            }
            ATTR_MSG_HANDLER => {
                if !(str_eq(a, b)
                    && *((a + ATTR_MSG_PD) as *const u8) == *((b + ATTR_MSG_PD) as *const u8)
                    && *((a + ATTR_MSG_SP) as *const u8) == *((b + ATTR_MSG_SP) as *const u8))
                {
                    return ATTRS_CHANGED;
                }
                handlers = true;
            }
            ATTR_PROPERTY_HANDLER => {
                if !(str_eq(a, b)
                    && str_eq(a + ATTR_PROPERTY_PROP, b + ATTR_PROPERTY_PROP)
                    && *((a + ATTR_PROPERTY_PD) as *const u8) == *((b + ATTR_PROPERTY_PD) as *const u8)
                    && *((a + ATTR_PROPERTY_SP) as *const u8) == *((b + ATTR_PROPERTY_SP) as *const u8))
                {
                    return ATTRS_CHANGED;
                }
                handlers = true;
            }
            ATTR_POINTER_HANDLER => {
                if !(str_eq(a, b)
                    && *((a + ATTR_POINTER_PD) as *const u8) == *((b + ATTR_POINTER_PD) as *const u8)
                    && *((a + ATTR_POINTER_SP) as *const u8) == *((b + ATTR_POINTER_SP) as *const u8))
                {
                    return ATTRS_CHANGED;
                }
                handlers = true;
            }
            ATTR_KEY_HANDLER => {
                if !(str_eq(a, b)
                    && *((a + ATTR_KEY_HANDLER_PD) as *const u8) == *((b + ATTR_KEY_HANDLER_PD) as *const u8)
                    && *((a + ATTR_KEY_HANDLER_SP) as *const u8) == *((b + ATTR_KEY_HANDLER_SP) as *const u8)
                    && key_lists_eq(a + ATTR_KEY_HANDLER_KEYS, b + ATTR_KEY_HANDLER_KEYS))
                {
                    return ATTRS_CHANGED;
                }
                handlers = true;
            }
            _ => return ATTRS_CHANGED,
        }
    }
    if handlers {
        ATTRS_REFRESH
    } else {
        ATTRS_SAME
    }
}

/// Do two `List(Str)`s of key filters hold equal strings?
unsafe fn key_lists_eq(a: usize, b: usize) -> bool {
    let la = &*(a as *const abi::RocList<RocStr>);
    let lb = &*(b as *const abi::RocList<RocStr>);
    if la.length != lb.length {
        return false;
    }
    for k in 0..la.length {
        if !str_eq(
            la.elements as usize + k * size_of::<RocStr>(),
            lb.elements as usize + k * size_of::<RocStr>(),
        ) {
            return false;
        }
    }
    true
}

/// Emit the compact handler-id refresh for an element whose attributes are
/// unchanged apart from its freshly boxed handlers (see `attrs_delta`).
unsafe fn emit_refresh_handlers(my: usize, new_off: usize) {
    push(OP_REFRESH_HANDLERS);
    push(my as u32);
    let count_pos = CMD_LEN;
    push(0);
    let mut n: u32 = 0;
    let attrs = read_u32(new_off + ATTRS_OFFSET) as usize;
    let count = read_u32(new_off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
    for i in 0..count {
        let a = attrs + i * ATTR_STRIDE;
        let id = match *((a + ATTR_DISC_OFFSET) as *const u8) {
            ATTR_MSG_HANDLER => read_u32(a + ATTR_MSG_BOX),
            ATTR_PROPERTY_HANDLER => read_u32(a + ATTR_PROPERTY_CB),
            ATTR_POINTER_HANDLER => read_u32(a + ATTR_POINTER_CB),
            ATTR_KEY_HANDLER => read_u32(a + ATTR_KEY_HANDLER_CB),
            _ => continue,
        };
        let (np, nl) = str_at(a);
        push(np);
        push(nl);
        push(id);
        n += 1;
    }
    set_word(count_pos, n);
}

/// Do the `RocStr`s at offsets `a` and `b` hold equal bytes?
unsafe fn str_eq(a: usize, b: usize) -> bool {
    let (ap, al) = str_at(a);
    let (bp, bl) = str_at(b);
    if al != bl {
        return false;
    }
    if ap == bp {
        return true;
    }
    for i in 0..al as usize {
        if *((ap as usize + i) as *const u8) != *((bp as usize + i) as *const u8) {
            return false;
        }
    }
    true
}

/// Emit a REPLACE of node `idx` with a freshly built subtree, backpatching the
/// subtree's word count so the runtime knows how many words to consume.
unsafe fn replace(idx: usize, new_off: usize) {
    push(OP_REPLACE);
    push(idx as u32);
    let len_pos = CMD_LEN;
    push(0);
    let before = CMD_LEN;
    emit(new_off);
    set_word(len_pos, (CMD_LEN - before) as u32);
}

/// Byte equality of two (ptr, len) spans.
unsafe fn bytes_eq(ap: u32, al: u32, bp: u32, bl: u32) -> bool {
    if al != bl {
        return false;
    }
    for i in 0..al as usize {
        if *((ap as usize + i) as *const u8) != *((bp as usize + i) as *const u8) {
            return false;
        }
    }
    true
}

/// The Key attribute of the element at `off`, as (ptr, len) into its key
/// string. Text nodes and unkeyed elements have none.
unsafe fn node_key(off: usize) -> Option<(u32, u32)> {
    if *((off + DISC_OFFSET) as *const u8) != TAG_ELEMENT {
        return None;
    }
    let attrs = read_u32(off + ATTRS_OFFSET) as usize;
    let n = read_u32(off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
    for i in 0..n {
        let a = attrs + i * ATTR_STRIDE;
        if *((a + ATTR_DISC_OFFSET) as *const u8) == ATTR_KEY {
            return Some(str_at(a));
        }
    }
    None
}

/// Do an old and a new child denote the same node, such that patching one
/// into the other is right? Keyed elements match by key; unkeyed elements and
/// text match positionally (callers only ask about a shared position). A tag
/// change on a matched pair is `diff`'s problem (it REPLACEs in place).
unsafe fn same_identity(old_off: usize, new_off: usize) -> bool {
    let mut old_off = old_off;
    let mut new_off = new_off;
    let mut old_disc = *((old_off + DISC_OFFSET) as *const u8);
    let mut new_disc = *((new_off + DISC_OFFSET) as *const u8);
    // A lazy PAIR matches positionally without forcing the new thunk (the
    // whole point of lazy). A lazy on one side only is judged by its forced
    // content instead: the old side is already forced (table lookup), and
    // the new side is about to be forced by the diff or replace that
    // follows this pairing either way, so wrapping or unwrapping a region
    // in Html.lazy patches it in place instead of rebuilding it.
    if old_disc != new_disc {
        old_off = resolve(old_off);
        new_off = resolve(new_off);
        old_disc = *((old_off + DISC_OFFSET) as *const u8);
        new_disc = *((new_off + DISC_OFFSET) as *const u8);
    }
    if old_disc != new_disc {
        return false;
    }
    if old_disc == TAG_TEXT {
        return true;
    }
    match (node_key(old_off), node_key(new_off)) {
        (None, None) => true,
        (Some((ap, al)), Some((bp, bl))) => bytes_eq(ap, al, bp, bl),
        _ => false,
    }
}

/// Diff `old`→`new` (both Html node offsets), emitting patch ops. `my` is the
/// pre-order index of `old` in the previous tree.
unsafe fn diff(old_off: usize, new_off: usize, my: usize) {
    // A lazy pair is decided from the thunks alone, without forcing the new
    // one: same input → the retained subtree moves under the new thunk and
    // the whole region is skipped. A changed input forces the new thunk and
    // the forced trees are diffed as normal, so the region patches instead
    // of being rebuilt wholesale.
    if *((old_off + DISC_OFFSET) as *const u8) == TAG_LAZY
        && *((new_off + DISC_OFFSET) as *const u8) == TAG_LAZY
    {
        let old_cb = read_u32(old_off) as usize;
        let new_cb = read_u32(new_off) as usize;
        if old_cb == new_cb {
            return;
        }
        if lazy_same(old_cb, new_cb) {
            lazy_rekey(old_cb, new_cb);
            return;
        }
        // Changed input: the numbering pass wrote only this region's total
        // (see build_prev_counts), so fill the inner pre-order slots before
        // descending into the forced trees.
        let old_content = lazy_force(old_cb);
        build_prev_counts(old_content, my);
        diff(old_content, lazy_force(new_cb), my);
        return;
    }
    // Mixed kinds (lazy on one side only): the forced content is the node.
    // An old-side region gets its inner pre-order slots filled here for the
    // same reason as in the lazy-pair branch above.
    let old_was_lazy = *((old_off + DISC_OFFSET) as *const u8) == TAG_LAZY;
    let old_off = resolve(old_off);
    if old_was_lazy {
        build_prev_counts(old_off, my);
    }
    let new_off = resolve(new_off);
    let old_disc = *((old_off + DISC_OFFSET) as *const u8);
    let new_disc = *((new_off + DISC_OFFSET) as *const u8);

    // Different kind (text vs element) → replace.
    if old_disc != new_disc {
        replace(my, new_off);
        return;
    }

    if new_disc == TAG_TEXT {
        if !str_eq(old_off, new_off) {
            let (ptr, len) = str_at(new_off);
            push(OP_SET_TEXT);
            push(my as u32);
            push(ptr);
            push(len);
        }
        return;
    }

    // Shared-subtree shortcut: byte-identical payloads mean the tag string,
    // attrs list and children list are the very allocations retained from the
    // previous tree, which stays alive until after the diff. Shared Roc values
    // are immutable (copy-on-write copies at refcount > 1), so the two
    // subtrees are one value and there is nothing to emit or descend into.
    if bytes_eq(
        old_off as u32,
        DISC_OFFSET as u32,
        new_off as u32,
        DISC_OFFSET as u32,
    ) {
        return;
    }

    // Both elements. Different tag → replace the subtree.
    if !str_eq(old_off, new_off) {
        replace(my, new_off);
        return;
    }

    // Same element: handler boxes are new every render, so an element with
    // handlers always needs SOMETHING. When nothing else changed, a compact
    // id refresh replaces the full attribute rewrite. Either way, every
    // handler-carrying element in a diffed region gets its ids refreshed
    // before the previous tree's boxes are dropped, which is the invariant
    // `lazy_sweep` and `render_current` rely on.
    match attrs_delta(old_off, new_off) {
        ATTRS_SAME => {}
        ATTRS_REFRESH => emit_refresh_handlers(my, new_off),
        _ => {
            push(OP_PATCH_ATTRS);
            push(my as u32);
            let len_pos = CMD_LEN;
            push(0);
            let before = CMD_LEN;
            let new_attrs = read_u32(new_off + ATTRS_OFFSET) as usize;
            let n = read_u32(new_off + ATTRS_OFFSET + LIST_LEN_OFFSET) as usize;
            for i in 0..n {
                emit_attr(new_attrs + i * ATTR_STRIDE);
            }
            set_word(len_pos, (CMD_LEN - before) as u32);
        }
    }

    diff_children(my, old_off, new_off);
}

const NO_MATCH: u32 = 0xFFFF_FFFF;

/// Reconcile an element's child list: pair up old and new children, emit one
/// OP_REORDER when the list's shape changed (insert/remove/move/count), and
/// recurse into every matched pair. The pairing is the standard keyed
/// algorithm: sync matching prefix and suffix positionally, match the middle
/// by key, then mark a longest increasing subsequence of the matched old
/// positions as STAY so the runtime moves as few nodes as possible.
unsafe fn diff_children(parent_idx: usize, old_off: usize, new_off: usize) {
    let old_data = read_u32(old_off + CHILDREN_OFFSET) as usize;
    let old_n = read_u32(old_off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
    let new_data = read_u32(new_off + CHILDREN_OFFSET) as usize;
    let new_n = read_u32(new_off + CHILDREN_OFFSET + LIST_LEN_OFFSET) as usize;
    if old_n == 0 && new_n == 0 {
        return;
    }
    let old_at = |j: usize| old_data + j * NODE_STRIDE;
    let new_at = |k: usize| new_data + k * NODE_STRIDE;

    // Scratch, one allocation of u32 words: per old child [pre-order start,
    // used flag], per new child [matched old position, stay flag, LIS tails,
    // LIS prev links].
    let scratch = roc_alloc((2 * old_n + 4 * new_n) * 4, 4) as *mut u32;
    if scratch.is_null() {
        core::arch::wasm32::unreachable();
    }
    let starts = scratch;
    let old_used = scratch.add(old_n);
    let m4n = scratch.add(2 * old_n);
    let stay = scratch.add(2 * old_n + new_n);
    let tails = scratch.add(2 * old_n + 2 * new_n);
    let prevl = scratch.add(2 * old_n + 3 * new_n);

    // `next_idx` is the pre-order index of old child `j`; its subtree size is
    // a precomputed lookup (see PREV_COUNTS) rather than a fresh subtree walk.
    let mut next_idx = parent_idx + 1;
    for j in 0..old_n {
        *starts.add(j) = next_idx as u32;
        next_idx += prev_count(next_idx);
        *old_used.add(j) = 0;
    }
    // Everything the old children span in pre-order. A REORDER replaces
    // exactly this segment of the runtime's node list.
    let old_span = next_idx - (parent_idx + 1);
    for k in 0..new_n {
        *m4n.add(k) = NO_MATCH;
        *stay.add(k) = 0;
    }

    // 1. Sync the matching prefix; those pairs are in place.
    let mut lo = 0;
    while lo < old_n && lo < new_n && same_identity(old_at(lo), new_at(lo)) {
        *m4n.add(lo) = lo as u32;
        *stay.add(lo) = 1;
        *old_used.add(lo) = 1;
        lo += 1;
    }

    // 2. Sync the matching suffix. e1/e2 are exclusive ends of the middle.
    let mut e1 = old_n;
    let mut e2 = new_n;
    while e1 > lo && e2 > lo && same_identity(old_at(e1 - 1), new_at(e2 - 1)) {
        e1 -= 1;
        e2 -= 1;
        *m4n.add(e2) = e1 as u32;
        *stay.add(e2) = 1;
        *old_used.add(e1) = 1;
    }

    // 3. Match the middles by key (quadratic scan; middles are small in
    // practice, and keys should be unique among siblings). Unkeyed middle
    // children never match: old ones are removed, new ones built fresh.
    for k in lo..e2 {
        if let Some((np, nl)) = node_key(new_at(k)) {
            for j in lo..e1 {
                if *old_used.add(j) == 0 {
                    if let Some((op, ol)) = node_key(old_at(j)) {
                        if bytes_eq(np, nl, op, ol) {
                            *m4n.add(k) = j as u32;
                            *old_used.add(j) = 1;
                            break;
                        }
                    }
                }
            }
        }
    }

    // 4. Longest increasing subsequence of the middle's matched old
    // positions (patience algorithm): its members keep their relative order,
    // so they STAY and everything else MOVEs around them.
    let mut lis_len: usize = 0;
    for k in lo..e2 {
        let v = *m4n.add(k);
        if v == NO_MATCH {
            continue;
        }
        let mut a = 0;
        let mut b = lis_len;
        while a < b {
            let mid = (a + b) / 2;
            if *m4n.add(*tails.add(mid) as usize) < v {
                a = mid + 1;
            } else {
                b = mid;
            }
        }
        *prevl.add(k) = if a > 0 { *tails.add(a - 1) } else { NO_MATCH };
        *tails.add(a) = k as u32;
        if a == lis_len {
            lis_len += 1;
        }
    }
    if lis_len > 0 {
        let mut k = *tails.add(lis_len - 1);
        while k != NO_MATCH {
            *stay.add(k as usize) = 1;
            k = *prevl.add(k as usize);
        }
    }

    // Emit one REORDER whenever the list's shape changed. When every child
    // matched its own position (the common case), this is skipped entirely.
    let mut changed = old_n != new_n;
    for k in 0..new_n {
        if *m4n.add(k) == NO_MATCH || *stay.add(k) == 0 {
            changed = true;
        }
    }
    for j in 0..old_n {
        if *old_used.add(j) == 0 {
            changed = true;
        }
    }
    if changed {
        push(OP_REORDER);
        push(parent_idx as u32);
        push(old_span as u32);
        push(new_n as u32);
        for k in 0..new_n {
            let m = *m4n.add(k);
            if m == NO_MATCH {
                push(REORDER_NEW);
                let len_pos = CMD_LEN;
                push(0);
                let before = CMD_LEN;
                emit(new_at(k));
                set_word(len_pos, (CMD_LEN - before) as u32);
            } else {
                push(if *stay.add(k) == 1 { REORDER_STAY } else { REORDER_MOVE });
                push(m);
                let start = *starts.add(m as usize);
                push(start);
                push(prev_count(start as usize) as u32);
            }
        }
    }

    // Recurse into matched pairs. Their patches address old pre-order
    // indices, which stay valid through any reorder: the runtime resolves
    // indices to node references before mutating anything.
    for k in 0..new_n {
        let m = *m4n.add(k);
        if m != NO_MATCH {
            diff(old_at(m as usize), new_at(k), *starts.add(m as usize) as usize);
        }
    }

    roc_dealloc(scratch as *mut u8, 4);
}

/// Render the current model into the command buffer, a full build the first
/// time, a diff against the previous tree thereafter. The previous tree is
/// dropped once the diff has been emitted; everything the command buffer
/// references (strings, handler boxes) points into the NEW tree, and JS
/// paints before any further dispatch can run, so nothing dangles.
unsafe fn render_current() {
    incref(MODEL); // roc_render consumes one model ref; the host keeps its own
    if !HAVE_PREV {
        #[cfg(joy_bench)]
        let t0 = joy_bench_now();
        *(&raw mut ROOT as *mut Html) = abi::roc_render(MODEL as abi::RocBox);
        #[cfg(joy_bench)]
        let t1 = joy_bench_now();
        CMD_LEN = 0;
        push(MODE_FULL);
        emit(&raw const ROOT as usize);
        HAVE_PREV = true;
        #[cfg(joy_bench)]
        {
            BENCH_PHASE_MS[1] = t1 - t0;
            BENCH_PHASE_MS[2] = joy_bench_now() - t1;
        }
    } else {
        #[cfg(joy_bench)]
        let t0 = joy_bench_now();
        // Snapshot the current tree, then render the new one over ROOT.
        core::ptr::copy_nonoverlapping(
            &raw const ROOT as *const u8,
            &raw mut PREV_ROOT as *mut u8,
            NODE_STRIDE,
        );
        #[cfg(joy_bench)]
        let t1 = joy_bench_now();
        *(&raw mut ROOT as *mut Html) = abi::roc_render(MODEL as abi::RocBox);
        #[cfg(joy_bench)]
        let t2 = joy_bench_now();
        CMD_LEN = 0;
        push(MODE_PATCH);
        // Precompute the previous tree's pre-order subtree sizes once, so the
        // diff advances child indices by lookup instead of re-walking subtrees.
        let prev_total = count_nodes(&raw const PREV_ROOT as usize);
        ensure_prev_counts(prev_total);
        build_prev_counts(&raw const PREV_ROOT as usize, 0);
        diff(&raw const PREV_ROOT as usize, &raw const ROOT as usize, 0);
        // The dropper's Html got its own schema type id; same runtime type.
        abi::roc_drop_view(*(&raw const PREV_ROOT as *const abi::HtmlType99));
        // With the previous tree gone, retained lazy subtrees whose thunks
        // are no longer reachable can be dropped. Nothing allocates between
        // the drop above and this walk, so stale keys cannot alias.
        lazy_sweep();
        #[cfg(joy_bench)]
        {
            BENCH_PHASE_MS[1] = t2 - t1;
            BENCH_PHASE_MS[2] = (t1 - t0) + (joy_bench_now() - t2);
        }
    }
}

/// Allocate `len` bytes for JS to write string data into, returning the data
/// pointer. The allocation is prefixed with a refcount word set to 1, so a
/// `RocStr` built over it is an ordinary owned heap string that Roc frees
/// when it consumes it. JS calls this before `start`, `dispatch_value` and
/// the key dispatches.
#[no_mangle]
pub extern "C" fn js_alloc(len: usize) -> usize {
    unsafe {
        let p = roc_alloc(4 + len, 4) as usize;
        if p == 0 {
            core::arch::wasm32::unreachable();
        }
        *(p as *mut isize) = 1; // refcount: owned; Roc frees it when consumed
        p + 4
    }
}

/// A `RocStr` copied out of arbitrary memory. Values ≤ 11 bytes become
/// inline small strings, longer ones get a fresh refcounted allocation that
/// Roc frees when the string's refcount hits zero. The source bytes are left
/// alone.
unsafe fn str_copied(ptr: usize, len: usize) -> RocStr {
    if len <= 11 {
        let mut s = RocStr {
            bytes: core::ptr::null_mut(),
            capacity_or_alloc_ptr: 0,
            length: 0,
        };
        let dst = &raw mut s as *mut u8;
        for i in 0..len {
            *dst.add(i) = *((ptr + i) as *const u8);
        }
        *dst.add(11) = (len as u8) | 0x80; // small-string marker + length
        s
    } else {
        let block = roc_alloc(4 + len, 4) as usize;
        if block == 0 {
            core::arch::wasm32::unreachable();
        }
        *(block as *mut isize) = 1; // refcount: owned; Roc frees it when consumed
        core::ptr::copy_nonoverlapping(ptr as *const u8, (block + 4) as *mut u8, len);
        RocStr {
            bytes: (block + 4) as *mut u8,
            // Roc stores capacity SHIFTED LEFT ONE BIT (the low bit is the
            // seamless-slice tag, 0 here); the decoded capacity is `len`, so
            // capacity >= length holds. (Storing `(len+1)&!1` would decode to
            // roughly len/2 and violate that invariant inside Roc.)
            capacity_or_alloc_ptr: len << 1,
            length: len,
        }
    }
}

/// A `RocStr` taking ownership of the `js_alloc` block whose data starts at
/// `ptr`. Values ≤ 11 bytes become inline small strings and the block is
/// freed immediately (Roc never sees it); longer values hand the whole block
/// to Roc, which frees it when the string's refcount hits zero.
unsafe fn str_from_parts(ptr: usize, len: usize) -> RocStr {
    if len <= 11 {
        let s = str_copied(ptr, len);
        if ptr != 0 {
            roc_dealloc((ptr - 4) as *mut u8, 4); // the block is host-owned scratch
        }
        s
    } else {
        RocStr {
            bytes: ptr as *mut u8,
            // Same capacity encoding as str_copied's heap branch.
            capacity_or_alloc_ptr: len << 1,
            length: len,
        }
    }
}

// --- Effect queue ---
// `Effect(Msg)` layout facts (discriminants by name, payload field order
// chosen by the compiler, e.g. the timer payloads place the callback Box
// BEFORE the U32) all come from the generated bindings below. The `Cmd`
// names in the bindings and in the derived constants are the type's
// pre-rename schema names, kept so the committed bindings file and the
// exported `roc_drop_cmds` symbol stay stable.
//
// The host cannot start a fetch or a timer (the module is import-free), so
// each effect is serialised into this queue as u32 words and the JS runtime
// drains + executes them after every entry call:
//   HTTP:      [1, cb, method_ptr, method_len, url_ptr, url_len,
//                  body_ptr, body_len, timeout_lo, timeout_hi,
//                  n_headers, (np, nl, vp, vl) * n]
//   AFTER:     [2, cb, ms]
//   NAV:       [5|6|7, url_ptr, url_len]  (navigate | push_url | replace_url)
//   SUB START: [8, id, ms]   (from sync_subs, not run_cmds)
//   SUB STOP:  [9, id]       (from sync_subs; stops every kind of sub)
//   KEYBOARD:  [10, id, prevent_default, event_ptr, event_len,
//                  n_keys, (kp, kl) * n]   (from sync_subs)
//   PORT SEND: [11, name_ptr, name_len, value_ptr, value_len]
//   PORT START:[12, id, name_ptr, name_len]   (from sync_subs; incoming port)
//   URL START: [13, id]                        (from sync_subs; url change)
//   MODAL:     [14|15, sel_ptr, sel_len]  (show_modal | close_modal)
//   DEBOUNCE:  [16, cb, ms, key_ptr, key_len]
//   CANCEL:    [17, key_ptr, key_len]     (discard a pending debounce)
//   HTTP FILE: [18, cb, method_ptr, method_len, url_ptr, url_len, file_id,
//                  start_lo, start_hi, len_lo, len_hi, timeout_lo, timeout_hi,
//                  n_headers, (np, nl, vp, vl) * n]
//   DIGEST:    [19, cb, alg_ptr, alg_len, data_ptr, data_len]
//   DIGEST FILE: [20, cb, alg_ptr, alg_len, file_id,
//                  start_lo, start_hi, len_lo, len_hi]
// U64s cross as two u32 words, low first. Strings and bytes are pushed as
// host-owned copies (the effect list that produced them is dropped right
// after queuing); `effects_clear` frees them once JS has decoded the batch.
const CMD_STRIDE: usize = size_of::<Cmd>();
const CMD_DISC_OFFSET: usize = offset_of!(Cmd, tag);
const CMD_CLOSE_MODAL: u8 = CmdTag::CloseModal as u8;
const CMD_CONSOLE_LOG: u8 = CmdTag::ConsoleLog as u8;
const CMD_CRYPTO_DIGEST: u8 = CmdTag::CryptoDigest as u8;
const CMD_CRYPTO_DIGEST_FILE: u8 = CmdTag::CryptoDigestFile as u8;
const CMD_HTTP_SEND: u8 = CmdTag::HttpSend as u8;
const CMD_HTTP_SEND_FILE: u8 = CmdTag::HttpSendFile as u8;
const CMD_NAVIGATE: u8 = CmdTag::Navigate as u8;
const CMD_PORT_SEND: u8 = CmdTag::PortSend as u8;
const CMD_PUSH_URL: u8 = CmdTag::PushUrl as u8;
const CMD_REPLACE_URL: u8 = CmdTag::ReplaceUrl as u8;
const CMD_SHOW_MODAL: u8 = CmdTag::ShowModal as u8;
const CMD_TIME_AFTER: u8 = CmdTag::TimeAfter as u8;
const CMD_TIME_CANCEL: u8 = CmdTag::TimeCancel as u8;
const CMD_TIME_DEBOUNCE: u8 = CmdTag::TimeDebounce as u8;
// Payload field offsets. HttpSend(Str method, Str url, List headers,
// List(U8) body, U64 timeout, Box callback); PortSend(Str name, Str value);
// TimeAfter(Box callback, U32 ms). (Port.listen is a subscription now, not an
// Effect, see the Sub section.) The U64 timeouts and byte ranges sort ahead of
// everything else (align 8), and TimeDebounce's callable (_2) sorts ahead of
// its U32 (_1).
const HTTP_METHOD: usize = offset_of!(HttpSendPayload, _0);
const HTTP_URL: usize = offset_of!(HttpSendPayload, _1);
const HTTP_HEADERS: usize = offset_of!(HttpSendPayload, _2);
const HTTP_BODY: usize = offset_of!(HttpSendPayload, _3);
const HTTP_TIMEOUT: usize = offset_of!(HttpSendPayload, _4);
const HTTP_CALLBACK: usize = offset_of!(HttpSendPayload, _5);
const PORT_SEND_VALUE: usize = offset_of!(PortSendPayload, _1);
const TIMER_CALLBACK: usize = offset_of!(TimeAfterPayload, _0);
const TIMER_MS: usize = offset_of!(TimeAfterPayload, _1);
const HEADER_STRIDE: usize = size_of::<HeaderPair>();
// CryptoDigest(Str algorithm, List(U8) bytes, Box callback).
const CRYPTO_BYTES: usize = offset_of!(CryptoDigestPayload, _1);
const CRYPTO_CB: usize = offset_of!(CryptoDigestPayload, _2);
// CryptoDigestFile(Str algorithm, U32 file, U64 start, U64 len, Box callback).
const CRYPTO_FILE_ALG: usize = offset_of!(CryptoDigestFilePayload, _0);
const CRYPTO_FILE_ID: usize = offset_of!(CryptoDigestFilePayload, _1);
const CRYPTO_FILE_START: usize = offset_of!(CryptoDigestFilePayload, _2);
const CRYPTO_FILE_LEN: usize = offset_of!(CryptoDigestFilePayload, _3);
const CRYPTO_FILE_CB: usize = offset_of!(CryptoDigestFilePayload, _4);
// HttpSendFile(Str method, Str url, List headers, U32 file, U64 start,
// U64 len, U64 timeout, Box callback).
const HTTP_FILE_METHOD: usize = offset_of!(HttpSendFilePayload, _0);
const HTTP_FILE_URL: usize = offset_of!(HttpSendFilePayload, _1);
const HTTP_FILE_HEADERS: usize = offset_of!(HttpSendFilePayload, _2);
const HTTP_FILE_ID: usize = offset_of!(HttpSendFilePayload, _3);
const HTTP_FILE_START: usize = offset_of!(HttpSendFilePayload, _4);
const HTTP_FILE_LEN: usize = offset_of!(HttpSendFilePayload, _5);
const HTTP_FILE_TIMEOUT: usize = offset_of!(HttpSendFilePayload, _6);
const HTTP_FILE_CB: usize = offset_of!(HttpSendFilePayload, _7);
// TimeDebounce(Str key, U32 ms, Box callback).
const DEBOUNCE_MS: usize = offset_of!(TimeDebouncePayload, _1);
const DEBOUNCE_CB: usize = offset_of!(TimeDebouncePayload, _2);

// `List(Sub(msg))` element layout: the Sub union, whose per-variant record
// sits at payload offset 0 (see `SubEvery` / `SubKeyboard`).
const SUB_STRIDE: usize = size_of::<Sub>();
const SUB_DISC_OFFSET: usize = offset_of!(Sub, tag);
const SUB_TAG_EVERY: u8 = SubTag::Every as u8;
const SUB_TAG_KEYBOARD: u8 = SubTag::Keyboard as u8;
const SUB_TAG_PORT_LISTEN: u8 = SubTag::PortListen as u8;
const SUB_TAG_URL_CHANGED: u8 = SubTag::UrlChanged as u8;
const EVERY_CB: usize = offset_of!(SubEvery, on_tick);
const EVERY_MS: usize = offset_of!(SubEvery, ms);
const KB_EVENT: usize = offset_of!(SubKeyboard, event);
const KB_KEYS: usize = offset_of!(SubKeyboard, keys);
const KB_CB: usize = offset_of!(SubKeyboard, on_key);
const KB_PD: usize = offset_of!(SubKeyboard, prevent_default);
const PORT_LISTEN_NAME: usize = offset_of!(SubPortListen, name);
const PORT_LISTEN_CB: usize = offset_of!(SubPortListen, on_value);
const URL_CHANGED_CB: usize = offset_of!(SubUrlChanged, on_change);

const EFFECT_HTTP: u32 = 1;
const EFFECT_AFTER: u32 = 2;
// 3 was EFFECT_EVERY; retired when Time.every became a subscription.
// 4 was EFFECT_PORT (Port.listen as an effect); retired when it became a Sub
// (it now starts via EFFECT_PORT_START below).
const EFFECT_NAVIGATE: u32 = 5;
const EFFECT_PUSH_URL: u32 = 6;
const EFFECT_REPLACE_URL: u32 = 7;
const EFFECT_SUB_START: u32 = 8; // [8, id, ms]
const EFFECT_SUB_STOP: u32 = 9; // [9, id]
const EFFECT_KEYBOARD_START: u32 = 10; // [10, id, prevent_default, event_ptr, event_len, n_keys, (kp, kl) * n]
const EFFECT_PORT_SEND: u32 = 11; // [11, name_ptr, name_len, value_ptr, value_len]
const EFFECT_PORT_START: u32 = 12; // [12, id, name_ptr, name_len] (incoming-port sub)
const EFFECT_URL_START: u32 = 13; // [13, id] (url-change sub)
const EFFECT_SHOW_MODAL: u32 = 14; // [14, sel_ptr, sel_len]
const EFFECT_CLOSE_MODAL: u32 = 15; // [15, sel_ptr, sel_len]
const EFFECT_DEBOUNCE: u32 = 16; // [16, cb, ms, key_ptr, key_len]
const EFFECT_TIME_CANCEL: u32 = 17; // [17, key_ptr, key_len]
const EFFECT_HTTP_FILE: u32 = 18; // [18, cb, method, url, file_id, start x2, len x2, n_headers, (k, v) * n]
const EFFECT_CRYPTO_DIGEST: u32 = 19; // [19, cb, alg_ptr, alg_len, data_ptr, data_len]
const EFFECT_CRYPTO_DIGEST_FILE: u32 = 20; // [20, cb, alg, file_id, start x2, len x2]

static mut EFFECTS_PTR: usize = 0;
static mut EFFECTS_CAP: usize = 0;
static mut EFFECTS_LEN: usize = 0;

#[inline]
unsafe fn push_effect(word: u32) {
    buf_push(&mut EFFECTS_PTR, &mut EFFECTS_CAP, &mut EFFECTS_LEN, EFFECTS_INITIAL, word);
}

/// Copy `len` bytes at `ptr` into a fresh host-owned allocation and push the
/// (copy_ptr, len) pair. The effect list that owns the originals is dropped
/// right after queuing, but JS drains the queue later, so the queue must own
/// plain copies. `effects_clear` frees them.
unsafe fn push_effect_copy(ptr: usize, len: usize) {
    if len == 0 {
        push_effect(0);
        push_effect(0);
        return;
    }
    let copy = roc_alloc(len, 1);
    if copy.is_null() {
        core::arch::wasm32::unreachable();
    }
    core::ptr::copy_nonoverlapping(ptr as *const u8, copy, len);
    push_effect(copy as u32);
    push_effect(len as u32);
}

unsafe fn push_effect_str(off: usize) {
    let (p, l) = str_at(off);
    push_effect_copy(p as usize, l as usize);
}

/// Push the u64 at `off` as two u32 words, low first (matching how the
/// runtime reassembles byte offsets that can exceed 4GB files' 32 bits).
unsafe fn push_effect_u64(off: usize) {
    push_effect(read_u32(off));
    push_effect(read_u32(off + 4));
}

/// Serialise every effect in a `List(Effect(Msg))` into the effects queue.
/// Strings and bytes are copied (host-owned, freed by `effects_clear`);
/// callbacks the JS side will hold are increfed, so the caller can drop the
/// effect list immediately afterwards. Generic because each entry point's
/// effect list carries its own glue schema id for the same runtime type.
unsafe fn run_cmds<T>(cmds: &abi::RocList<T>) {
    let data = cmds.elements as usize;
    for i in 0..cmds.length {
        let c = data + i * CMD_STRIDE;
        match *((c + CMD_DISC_OFFSET) as *const u8) {
            CMD_HTTP_SEND => {
                let cb = read_u32(c + HTTP_CALLBACK) as usize;
                incref(cb); // held by JS until the response dispatches
                push_effect(EFFECT_HTTP);
                push_effect(cb as u32);
                push_effect_str(c + HTTP_METHOD);
                push_effect_str(c + HTTP_URL);
                let body = &*((c + HTTP_BODY) as *const abi::RocListWith<u8, false>);
                push_effect_copy(body.elements as usize, body.length);
                push_effect_u64(c + HTTP_TIMEOUT);
                let headers = &*((c + HTTP_HEADERS) as *const abi::RocList<HeaderPair>);
                push_effect(headers.length as u32);
                let hdata = headers.elements as usize;
                for h in 0..headers.length {
                    let pair = hdata + h * HEADER_STRIDE;
                    push_effect_str(pair + offset_of!(HeaderPair, name));
                    push_effect_str(pair + offset_of!(HeaderPair, value));
                }
            }
            CMD_HTTP_SEND_FILE => {
                let cb = read_u32(c + HTTP_FILE_CB) as usize;
                incref(cb); // held by JS until the response dispatches
                push_effect(EFFECT_HTTP_FILE);
                push_effect(cb as u32);
                push_effect_str(c + HTTP_FILE_METHOD);
                push_effect_str(c + HTTP_FILE_URL);
                push_effect(read_u32(c + HTTP_FILE_ID));
                push_effect_u64(c + HTTP_FILE_START);
                push_effect_u64(c + HTTP_FILE_LEN);
                push_effect_u64(c + HTTP_FILE_TIMEOUT);
                let headers = &*((c + HTTP_FILE_HEADERS) as *const abi::RocList<HeaderPair>);
                push_effect(headers.length as u32);
                let hdata = headers.elements as usize;
                for h in 0..headers.length {
                    let pair = hdata + h * HEADER_STRIDE;
                    push_effect_str(pair + offset_of!(HeaderPair, name));
                    push_effect_str(pair + offset_of!(HeaderPair, value));
                }
            }
            CMD_PORT_SEND => {
                push_effect(EFFECT_PORT_SEND);
                push_effect_str(c); // port name
                push_effect_str(c + PORT_SEND_VALUE);
            }
            // The msg-free effects each carry a single Str at payload
            // offset 0 and map straight onto their effect kind.
            CMD_NAVIGATE => {
                push_effect(EFFECT_NAVIGATE);
                push_effect_str(c); // url
            }
            CMD_PUSH_URL => {
                push_effect(EFFECT_PUSH_URL);
                push_effect_str(c); // url
            }
            CMD_REPLACE_URL => {
                push_effect(EFFECT_REPLACE_URL);
                push_effect_str(c); // url
            }
            CMD_SHOW_MODAL => {
                push_effect(EFFECT_SHOW_MODAL);
                push_effect_str(c); // CSS selector
            }
            CMD_CLOSE_MODAL => {
                push_effect(EFFECT_CLOSE_MODAL);
                push_effect_str(c); // CSS selector
            }
            CMD_TIME_CANCEL => {
                push_effect(EFFECT_TIME_CANCEL);
                push_effect_str(c); // debounce key
            }
            // ConsoleLog delivers through the console queue rather than the
            // effects queue: the runtime drains both on the same entry call.
            CMD_CONSOLE_LOG => {
                let (ptr, len) = str_at(c);
                log_push_copy(ptr as *const u8, len as usize, LOG_LEVEL_LOG);
            }
            CMD_TIME_AFTER => {
                let cb = read_u32(c + TIMER_CALLBACK) as usize;
                incref(cb); // held by JS until the timer fires
                push_effect(EFFECT_AFTER);
                push_effect(cb as u32);
                push_effect(read_u32(c + TIMER_MS));
            }
            CMD_TIME_DEBOUNCE => {
                let cb = read_u32(c + DEBOUNCE_CB) as usize;
                incref(cb); // held by JS until the timer fires or is re-armed
                push_effect(EFFECT_DEBOUNCE);
                push_effect(cb as u32);
                push_effect(read_u32(c + DEBOUNCE_MS));
                push_effect_str(c); // debounce key
            }
            CMD_CRYPTO_DIGEST => {
                let cb = read_u32(c + CRYPTO_CB) as usize;
                incref(cb); // held by JS until the digest dispatches
                push_effect(EFFECT_CRYPTO_DIGEST);
                push_effect(cb as u32);
                push_effect_str(c); // algorithm
                let bytes = &*((c + CRYPTO_BYTES) as *const abi::RocListWith<u8, false>);
                push_effect_copy(bytes.elements as usize, bytes.length);
            }
            CMD_CRYPTO_DIGEST_FILE => {
                let cb = read_u32(c + CRYPTO_FILE_CB) as usize;
                incref(cb); // held by JS until the digest dispatches
                push_effect(EFFECT_CRYPTO_DIGEST_FILE);
                push_effect(cb as u32);
                push_effect_str(c + CRYPTO_FILE_ALG);
                push_effect(read_u32(c + CRYPTO_FILE_ID));
                push_effect_u64(c + CRYPTO_FILE_START);
                push_effect_u64(c + CRYPTO_FILE_LEN);
            }
            _ => {}
        }
    }
}

/// Recursively free a `List(Effect(Msg))` via the consuming dropper entry point.
/// The dropper's Effect carries its own glue schema id, the runtime type is
/// identical, so the 12-byte list header is reread as the dropper's type.
unsafe fn drop_cmds<T>(cmds: &abi::RocList<T>) {
    abi::roc_drop_cmds(*(cmds as *const abi::RocList<T> as *const abi::RocList<abi::CmdType114>));
}

// --- Subscriptions ---
// The app declares its recurring event sources as data (`subscriptions :
// model -> List(Sub(msg))`); after every model change the host diffs that
// list against the live table below. Same identity = the running source is
// kept and only the callbacks swap in (they may capture new model state, the
// same stale-closure rule as DOM event handlers); a new identity starts a
// source; a missing one stops it, so cancellation is by omission and nothing
// outlives the subscription list that declared it.
//
// Identity is the variant plus its parameters: for `Every` the interval, for
// `Keyboard` the (event, keys, prevent_default) triple, which the table
// stores as a host-owned byte blob (`[len u32][prevent_default u8][event]
// [0]([key][0])*`) because the strings live in the transient sub list.
//
// Entries are u32 quads [kind, ident, cb-list, live-mark]; ident is the ms
// value for a timer and the blob pointer for keyboard. cb-list points at a
// host-owned `[cap u32][len u32][cb u32 * len]` blob holding EVERY callback
// declared for the identity this round: duplicate subscriptions share the
// one running source, and each firing delivers all their messages in
// declaration order instead of the last silently winning. The slot index is
// the id JS keys its cleanup handles on. kind 0 marks a free slot. A slot
// freed by a stop is reusable immediately: JS runs the cleanup while draining
// the same effects batch that could start a successor, and both clearInterval
// and removeEventListener also cancel already-queued firings.
const SUB_WORDS: usize = 4;
const SUB_FREE: u32 = 0;
const SUB_EVERY: u32 = 1;
const SUB_KEYBOARD: u32 = 2;
const SUB_PORT: u32 = 3;
const SUB_URL: u32 = 4;
// UrlChanged carries no parameters, so every url-change sub shares one
// identity: a fixed non-zero sentinel, value-compared like a timer's ms.
const URL_IDENT: u32 = 1;
static mut SUBS_PTR: usize = 0;
static mut SUBS_CAP: usize = 0; // in entries

#[inline]
unsafe fn sub_slot(i: usize) -> *mut u32 {
    (SUBS_PTR + i * SUB_WORDS * 4) as *mut u32
}

/// A free table slot, growing the table when none is left.
unsafe fn take_sub_slot() -> usize {
    for s in 0..SUBS_CAP {
        if *sub_slot(s) == SUB_FREE {
            return s;
        }
    }
    let old_cap = SUBS_CAP;
    let new_cap = if old_cap == 0 { 8 } else { old_cap * 2 };
    let bytes = new_cap * SUB_WORDS * 4;
    let new_ptr = if SUBS_PTR == 0 {
        roc_alloc(bytes, 4)
    } else {
        roc_realloc(SUBS_PTR as *mut u8, bytes, 4)
    } as usize;
    if new_ptr == 0 {
        core::arch::wasm32::unreachable();
    }
    SUBS_PTR = new_ptr;
    SUBS_CAP = new_cap;
    for s in old_cap..new_cap {
        *sub_slot(s) = SUB_FREE;
    }
    old_cap
}

/// Recursively free a `List(Sub(Msg))` via its consuming dropper (same
/// schema-id bridging as `drop_cmds`).
unsafe fn drop_subs(subs: &abi::RocList<Sub>) {
    abi::roc_drop_subs(*(subs as *const abi::RocList<Sub> as *const abi::RocList<abi::SubType123>));
}

/// Build a keyboard sub's identity blob from its record at `e` (see the
/// table comment for the layout). Host-owned; freed when the sub stops or
/// when the blob turns out to match an existing slot.
unsafe fn build_kb_ident(e: usize) -> usize {
    let (ev_ptr, ev_len) = str_at(e + KB_EVENT);
    let keys = &*((e + KB_KEYS) as *const abi::RocList<RocStr>);
    let mut len = 1 + ev_len as usize + 1;
    for k in 0..keys.length {
        let (_, kl) = str_at(keys.elements as usize + k * size_of::<RocStr>());
        len += kl as usize + 1;
    }
    let blob = roc_alloc(4 + len, 4) as usize;
    if blob == 0 {
        core::arch::wasm32::unreachable();
    }
    *(blob as *mut u32) = len as u32;
    let mut w = blob + 4;
    *(w as *mut u8) = *((e + KB_PD) as *const u8);
    w += 1;
    core::ptr::copy_nonoverlapping(ev_ptr as *const u8, w as *mut u8, ev_len as usize);
    w += ev_len as usize;
    *(w as *mut u8) = 0;
    w += 1;
    for k in 0..keys.length {
        let (kp, kl) = str_at(keys.elements as usize + k * size_of::<RocStr>());
        core::ptr::copy_nonoverlapping(kp as *const u8, w as *mut u8, kl as usize);
        w += kl as usize;
        *(w as *mut u8) = 0;
        w += 1;
    }
    blob
}

unsafe fn kb_ident_eq(a: usize, b: usize) -> bool {
    let al = *(a as *const u32);
    bytes_eq((a + 4) as u32, al, (b + 4) as u32, *(b as *const u32))
}

/// Build a `[len u32][name bytes]` identity blob from the `Str` at `off` (a
/// port subscription's name). Same blob shape as `build_kb_ident`, so
/// `kb_ident_eq` compares them. Host-owned; freed when the sub stops or when
/// it turns out to match an existing slot.
unsafe fn build_name_ident(off: usize) -> usize {
    let (ptr, len) = str_at(off);
    let blob = roc_alloc(4 + len as usize, 4) as usize;
    if blob == 0 {
        core::arch::wasm32::unreachable();
    }
    *(blob as *mut u32) = len;
    core::ptr::copy_nonoverlapping(ptr as *const u8, (blob + 4) as *mut u8, len as usize);
    blob
}

/// Find the active slot matching (kind, ident); ident comparison is by value
/// for timers and by blob content for keyboard.
unsafe fn find_sub_slot(kind: u32, ident: usize) -> usize {
    for s in 0..SUBS_CAP {
        let p = sub_slot(s);
        if *p != kind {
            continue;
        }
        let stored = *p.add(1) as usize;
        let hit = match kind {
            // Keyboard and port identities are `[len][bytes]` blobs, compared
            // by content; timer (ms) and url (sentinel) are compared by value.
            SUB_KEYBOARD | SUB_PORT => kb_ident_eq(stored, ident),
            _ => stored == ident,
        };
        if hit {
            return s;
        }
    }
    usize::MAX
}

/// A fresh, empty callback-list blob (`[cap][len][cb*]`, see the table
/// comment).
unsafe fn cb_list_new() -> usize {
    let blob = roc_alloc(8 + 2 * 4, 4) as usize;
    if blob == 0 {
        core::arch::wasm32::unreachable();
    }
    *(blob as *mut u32) = 2; // cap
    *((blob + 4) as *mut u32) = 0; // len
    blob
}

#[inline]
unsafe fn cb_list_len(blob: usize) -> usize {
    *((blob + 4) as *const u32) as usize
}

#[inline]
unsafe fn cb_at(blob: usize, i: usize) -> usize {
    *((blob + 8 + i * 4) as *const u32) as usize
}

/// Release a stored sub callback through the dropper matching its type
/// (uniform in practice, since boxed erased callables carry their own
/// on_drop, but kept per-kind so the schema ids line up).
unsafe fn drop_sub_callback(kind: u32, cb: usize) {
    if kind == SUB_KEYBOARD {
        abi::roc_drop_key_callback(cb as abi::RocErasedCallable);
    } else if kind == SUB_PORT || kind == SUB_URL {
        // Both carry a `Str -> Box(msg)` decoder.
        abi::roc_drop_value_callback(cb as abi::RocErasedCallable);
    } else {
        abi::roc_drop_timer_callback(cb as abi::RocErasedCallable);
    }
}

/// Release every callback in slot `s`'s list and empty it (the blob stays).
unsafe fn cb_list_clear(s: usize) {
    let p = sub_slot(s);
    let blob = *p.add(2) as usize;
    for i in 0..cb_list_len(blob) {
        drop_sub_callback(*p, cb_at(blob, i));
    }
    *((blob + 4) as *mut u32) = 0;
}

/// Add `cb` to slot `s`'s callback list for this sync round. The round's
/// first declaration of the identity drops last round's callbacks and starts
/// a fresh list; later declarations append, so duplicate identities fan out
/// instead of collapsing. Release-old-then-retain-new is safe even when a
/// callback is the same box both rounds (a cached sub): the incoming sub
/// list owns a reference to every callback until `drop_subs` at the end of
/// `sync_subs`, so nothing can hit zero in between.
unsafe fn sub_add_callback(s: usize, cb: usize) {
    let p = sub_slot(s);
    if *p.add(3) == 0 {
        cb_list_clear(s);
        *p.add(3) = 1;
    }
    incref(cb);
    let mut blob = *p.add(2) as usize;
    let cap = *(blob as *const u32) as usize;
    let len = cb_list_len(blob);
    if len == cap {
        blob = roc_realloc(blob as *mut u8, 8 + cap * 2 * 4, 4) as usize;
        if blob == 0 {
            core::arch::wasm32::unreachable();
        }
        *(blob as *mut u32) = (cap * 2) as u32;
        *p.add(2) = blob as u32;
    }
    *((blob + 8 + len * 4) as *mut u32) = cb as u32;
    *((blob + 4) as *mut u32) = (len + 1) as u32;
}

/// Ask the app for its subscription list and reconcile the table with it,
/// queueing start/stop effects for JS. Runs after init and after every model
/// change. Duplicate identities within one list share one slot and all fire.
unsafe fn sync_subs() {
    incref(MODEL); // roc_subs consumes one model ref
    let subs = abi::roc_subs(MODEL as abi::RocBox);
    for s in 0..SUBS_CAP {
        *sub_slot(s).add(3) = 0;
    }
    let data = subs.elements as usize;
    for i in 0..subs.length {
        let e = data + i * SUB_STRIDE;
        match *((e + SUB_DISC_OFFSET) as *const u8) {
            SUB_TAG_EVERY => {
                let ms = read_u32(e + EVERY_MS);
                let cb = read_u32(e + EVERY_CB) as usize;
                let found = find_sub_slot(SUB_EVERY, ms as usize);
                if found != usize::MAX {
                    sub_add_callback(found, cb);
                } else {
                    let s = take_sub_slot();
                    let p = sub_slot(s);
                    *p = SUB_EVERY;
                    *p.add(1) = ms;
                    *p.add(2) = cb_list_new() as u32;
                    *p.add(3) = 0;
                    sub_add_callback(s, cb);
                    push_effect(EFFECT_SUB_START);
                    push_effect(s as u32);
                    push_effect(ms);
                }
            }
            SUB_TAG_KEYBOARD => {
                let cb = read_u32(e + KB_CB) as usize;
                let ident = build_kb_ident(e);
                let found = find_sub_slot(SUB_KEYBOARD, ident);
                if found != usize::MAX {
                    roc_dealloc(ident as *mut u8, 4); // slot already owns an equal blob
                    sub_add_callback(found, cb);
                } else {
                    let s = take_sub_slot();
                    let p = sub_slot(s);
                    *p = SUB_KEYBOARD;
                    *p.add(1) = ident as u32;
                    *p.add(2) = cb_list_new() as u32;
                    *p.add(3) = 0;
                    sub_add_callback(s, cb);
                    push_effect(EFFECT_KEYBOARD_START);
                    push_effect(s as u32);
                    push_effect(*((e + KB_PD) as *const u8) as u32);
                    push_effect_str(e + KB_EVENT);
                    let keys = &*((e + KB_KEYS) as *const abi::RocList<RocStr>);
                    push_effect(keys.length as u32);
                    for k in 0..keys.length {
                        push_effect_str(keys.elements as usize + k * size_of::<RocStr>());
                    }
                }
            }
            SUB_TAG_PORT_LISTEN => {
                let cb = read_u32(e + PORT_LISTEN_CB) as usize;
                let ident = build_name_ident(e + PORT_LISTEN_NAME);
                let found = find_sub_slot(SUB_PORT, ident);
                if found != usize::MAX {
                    roc_dealloc(ident as *mut u8, 4); // slot already owns an equal blob
                    sub_add_callback(found, cb);
                } else {
                    let s = take_sub_slot();
                    let p = sub_slot(s);
                    *p = SUB_PORT;
                    *p.add(1) = ident as u32;
                    *p.add(2) = cb_list_new() as u32;
                    *p.add(3) = 0;
                    sub_add_callback(s, cb);
                    push_effect(EFFECT_PORT_START);
                    push_effect(s as u32);
                    push_effect_str(e + PORT_LISTEN_NAME);
                }
            }
            SUB_TAG_URL_CHANGED => {
                let cb = read_u32(e + URL_CHANGED_CB) as usize;
                let found = find_sub_slot(SUB_URL, URL_IDENT as usize);
                if found != usize::MAX {
                    sub_add_callback(found, cb);
                } else {
                    let s = take_sub_slot();
                    let p = sub_slot(s);
                    *p = SUB_URL;
                    *p.add(1) = URL_IDENT;
                    *p.add(2) = cb_list_new() as u32;
                    *p.add(3) = 0;
                    sub_add_callback(s, cb);
                    push_effect(EFFECT_URL_START);
                    push_effect(s as u32);
                }
            }
            _ => {}
        }
    }
    for s in 0..SUBS_CAP {
        let p = sub_slot(s);
        if *p != SUB_FREE && *p.add(3) == 0 {
            push_effect(EFFECT_SUB_STOP);
            push_effect(s as u32);
            if *p == SUB_KEYBOARD || *p == SUB_PORT {
                // Keyboard and port slots own a `[len][bytes]` identity blob.
                roc_dealloc((*p.add(1)) as usize as *mut u8, 4);
            }
            cb_list_clear(s);
            roc_dealloc((*p.add(2)) as usize as *mut u8, 4);
            *p = SUB_FREE;
        }
    }
    drop_subs(&subs);
}

/// Scratch buffer for `n` collected msg-box words.
unsafe fn msg_scratch(n: usize) -> *mut u32 {
    let p = roc_alloc(if n == 0 { 4 } else { n * 4 }, 4) as *mut u32;
    if p.is_null() {
        core::arch::wasm32::unreachable();
    }
    p
}

/// Apply `n` collected msg boxes in order, then render and re-sync the subs
/// once. Frees the scratch buffer.
///
/// Messages are collected before any is applied: callbacks only produce
/// messages (they cannot reach the table), while `update` can rewrite the
/// very callback list being walked, and each `render_current` resets the
/// command buffer so only the last of several renders would ever be painted.
/// One render over the final model is also what a burst of messages should
/// look like.
unsafe fn finish_msgs(msgs: *mut u32, n: usize) -> u32 {
    for i in 0..n {
        apply_msg(*msgs.add(i) as usize);
    }
    roc_dealloc(msgs as *mut u8, 4);
    if n > 0 {
        render_current();
        sync_subs();
        1
    } else {
        0
    }
}

/// Dispatch a timer subscription firing: look up the sub's CURRENT callbacks
/// (the table swaps in fresh ones on every model change, so a long-lived JS
/// interval never runs a stale closure), call each with the time, and apply
/// the messages. A late fire against a freed or repurposed slot is a no-op.
#[no_mangle]
pub extern "C" fn dispatch_sub(id: usize, now_ms: f64) -> u32 {
    unsafe {
        if id >= SUBS_CAP || *sub_slot(id) != SUB_EVERY {
            return 0;
        }
        // Calling a callable consumes its ARGS, not the callable's own ref
        // (dispatch_timer relies on the same fact), so the table's refs
        // cover any number of firings.
        let blob = *sub_slot(id).add(2) as usize;
        let n = cb_list_len(blob);
        let msgs = msg_scratch(n);
        for i in 0..n {
            let args: i64 = now_ms as i64;
            *msgs.add(i) = call_callable(cb_at(blob, i), &raw const args as *const u8) as u32;
        }
        finish_msgs(msgs, n)
    }
}

/// Dispatch a keyboard subscription firing: build the `KeyEvent` record from
/// what JS wrote via `js_alloc` (key and code strings, packed modifier and
/// repeat flags), call each of the slot's current callbacks with it, and
/// apply the messages. A late fire against a freed or repurposed slot is a
/// no-op.
#[no_mangle]
pub extern "C" fn dispatch_sub_key(
    id: usize,
    key_ptr: usize,
    key_len: usize,
    code_ptr: usize,
    code_len: usize,
    flags: u32,
) -> u32 {
    unsafe {
        let key = str_from_parts(key_ptr, key_len);
        let code = str_from_parts(code_ptr, code_len);
        if id >= SUBS_CAP || *sub_slot(id) != SUB_KEYBOARD {
            abi::roc_drop_str(key); // late fire: still own the JS blocks
            abi::roc_drop_str(code);
            return 0;
        }
        let blob = *sub_slot(id).add(2) as usize;
        let n = cb_list_len(blob);
        let msgs = msg_scratch(n);
        for i in 0..n {
            // Each call consumes the record's strings; add a reference per
            // extra callback so every call owns its own.
            if i + 1 < n {
                str_incref(&key);
                str_incref(&code);
            }
            let args = key_event_args(key, code, flags);
            *msgs.add(i) = call_callable(cb_at(blob, i), &raw const args as *const u8) as u32;
        }
        if n == 0 {
            abi::roc_drop_str(key);
            abi::roc_drop_str(code);
        }
        finish_msgs(msgs, n)
    }
}

/// Dispatch a value-carrying subscription firing: an incoming port value
/// (`app.sendPort`) or a URL change (`popstate`). JS wrote the string via
/// `js_alloc`; build a `Str`, call each of the slot's current
/// `Str -> Box(Msg)` decoders with it (fanning out to duplicate subs), and
/// apply the messages. A late fire against a freed or repurposed slot is a
/// no-op. Mirrors `dispatch_sub_key` but with a single `Str` argument.
#[no_mangle]
pub extern "C" fn dispatch_sub_value(id: usize, val_ptr: usize, val_len: usize) -> u32 {
    unsafe {
        let value = str_from_parts(val_ptr, val_len);
        if id >= SUBS_CAP || (*sub_slot(id) != SUB_PORT && *sub_slot(id) != SUB_URL) {
            abi::roc_drop_str(value); // late fire: still own the JS block
            return 0;
        }
        let blob = *sub_slot(id).add(2) as usize;
        let n = cb_list_len(blob);
        let msgs = msg_scratch(n);
        for i in 0..n {
            // Each call consumes the string; add a reference per extra
            // callback so every call owns its own.
            if i + 1 < n {
                str_incref(&value);
            }
            *msgs.add(i) = call_callable(cb_at(blob, i), &raw const value as *const u8) as u32;
        }
        if n == 0 {
            abi::roc_drop_str(value);
        }
        finish_msgs(msgs, n)
    }
}

#[no_mangle]
pub extern "C" fn effects_ptr() -> usize {
    unsafe { EFFECTS_PTR }
}

#[no_mangle]
pub extern "C" fn effects_len() -> usize {
    unsafe { EFFECTS_LEN }
}

/// Free one (ptr, len) copy the queue owns; returns the next word index.
unsafe fn free_effect_copy(w: *const u32, i: usize) -> usize {
    let ptr = *w.add(i) as usize;
    if ptr != 0 {
        roc_dealloc(ptr as *mut u8, 1);
    }
    i + 2
}

/// Clear the effects queue, freeing the string/byte copies it owns. JS calls
/// this after it has decoded everything (see parseEffects in the runtime).
#[no_mangle]
pub extern "C" fn effects_clear() {
    unsafe {
        let w = EFFECTS_PTR as *const u32;
        let n = EFFECTS_LEN;
        let mut i = 0;
        while i < n {
            let kind = *w.add(i);
            i += 1;
            if kind == EFFECT_HTTP {
                i += 1; // callback
                i = free_effect_copy(w, i); // method
                i = free_effect_copy(w, i); // url
                i = free_effect_copy(w, i); // body
                i += 2; // timeout (2 words)
                let n_headers = *w.add(i) as usize;
                i += 1;
                for _ in 0..n_headers {
                    i = free_effect_copy(w, i); // key
                    i = free_effect_copy(w, i); // value
                }
            } else if kind == EFFECT_AFTER || kind == EFFECT_SUB_START {
                i += 2; // callback/id, ms
            } else if kind == EFFECT_SUB_STOP {
                i += 1; // id
            } else if kind == EFFECT_KEYBOARD_START {
                i += 2; // id, prevent_default
                i = free_effect_copy(w, i); // event name
                let n_keys = *w.add(i) as usize;
                i += 1;
                for _ in 0..n_keys {
                    i = free_effect_copy(w, i); // key
                }
            } else if kind == EFFECT_PORT_SEND {
                i = free_effect_copy(w, i); // name
                i = free_effect_copy(w, i); // value
            } else if kind == EFFECT_PORT_START {
                i += 1; // id
                i = free_effect_copy(w, i); // name
            } else if kind == EFFECT_URL_START {
                i += 1; // id
            } else if kind == EFFECT_DEBOUNCE {
                i += 2; // callback, ms
                i = free_effect_copy(w, i); // key
            } else if kind == EFFECT_HTTP_FILE {
                i += 1; // callback
                i = free_effect_copy(w, i); // method
                i = free_effect_copy(w, i); // url
                i += 7; // file id, start (2 words), len (2 words), timeout (2 words)
                let n_headers = *w.add(i) as usize;
                i += 1;
                for _ in 0..n_headers {
                    i = free_effect_copy(w, i); // key
                    i = free_effect_copy(w, i); // value
                }
            } else if kind == EFFECT_CRYPTO_DIGEST {
                i += 1; // callback
                i = free_effect_copy(w, i); // algorithm
                i = free_effect_copy(w, i); // data
            } else if kind == EFFECT_CRYPTO_DIGEST_FILE {
                i += 1; // callback
                i = free_effect_copy(w, i); // algorithm
                i += 5; // file id, start (2 words), len (2 words)
            } else {
                // EFFECT_NAVIGATE / EFFECT_PUSH_URL / EFFECT_REPLACE_URL /
                // EFFECT_SHOW_MODAL / EFFECT_CLOSE_MODAL / EFFECT_TIME_CANCEL
                i = free_effect_copy(w, i); // url / selector / key
            }
        }
        EFFECTS_LEN = 0;
    }
}

/// Run `update` with an owned `Box(Msg)` reference and queue any effects,
/// WITHOUT rendering. Callers render (and re-sync subscriptions) themselves
/// so a batch of messages paints once.
///
/// Ownership: the host keeps its own +1 on MODEL across the call (incref
/// before, because `update` consumes one model ref). The old box is dropped
/// and the returned one adopted. The msg ref passed in is consumed by
/// `update`.
unsafe fn apply_msg(msg_box: usize) {
    #[cfg(joy_bench)]
    let t0 = joy_bench_now();
    incref(MODEL);
    let ret = abi::roc_update(MODEL as abi::RocBox, msg_box as abi::RocBox);
    abi::roc_drop_model(MODEL as abi::RocBox);
    MODEL = ret._0 as usize;
    run_cmds(&ret._1);
    drop_cmds(&ret._1);
    #[cfg(joy_bench)]
    {
        BENCH_PHASE_MS[0] = joy_bench_now() - t0;
    }
}

/// `apply_msg`, then render and re-sync subscriptions. An unchanged model
/// diffs to an empty patch, so the paint is a no-op then.
unsafe fn run_update(msg_box: usize) -> u32 {
    apply_msg(msg_box);
    render_current();
    sync_subs();
    1
}

/// Initialise the app: hand the flags string JS wrote via `js_alloc` to the
/// app's pure `init`, queue init's effects, then render. JS calls this once
/// on mount. Pass (0, 0) for no flags.
#[no_mangle]
pub extern "C" fn start(flags_ptr: usize, flags_len: usize) {
    unsafe {
        // init_for_host : Str -> (Box(Model), List(Effect(Msg))): box _0, effects _1.
        let ret = abi::roc_init(str_from_parts(flags_ptr, flags_len));
        MODEL = ret._0 as usize;
        run_cmds(&ret._1);
        drop_cmds(&ret._1);
        render_current();
        sync_subs();
    }
}

/// Dispatch a message into `update`. `msg_box` is the opaque `Box(Msg)`
/// pointer the host emitted in an OP_MSG_EVENT, JS hands it straight back.
///
/// The box is owned by the current render tree and may be dispatched many
/// times (repeated clicks), while `update` consumes one reference per call,
/// so incref before each dispatch to keep the tree's reference intact.
#[no_mangle]
pub extern "C" fn dispatch(msg_box: usize) -> u32 {
    unsafe {
        incref(msg_box);
        run_update(msg_box)
    }
}

// The erased-callable ABI comes from the generated bindings: a boxed callable
// is a refcounted allocation whose data starts with `RocErasedCallablePayload
// { callable_fn_ptr, on_drop }`; the closure's capture bytes live inline at
// the generated `ROC_ERASED_CALLABLE_CAPTURE_OFFSET`. The function pointer has
// the uniform shape `fn(host, ret, args, capture, reuse)`. Compiled Roc code
// carries no host context under the symbol ABI and passes null, so the host
// does the same. `reuse` is null for the same reason. It would hand the callee
// an owned reference to reuse in place, and the host has none to give.

/// Call the boxed callable with an args buffer, returning the produced
/// `Box(Msg)` pointer.
unsafe fn call_callable(callable: usize, args: *const u8) -> usize {
    let payload = &*(callable as *const abi::RocErasedCallablePayload);
    let mut msg_box: usize = 0;
    (payload.callable_fn_ptr)(
        core::ptr::null_mut(), // null host context, exactly as compiled Roc code passes
        &raw mut msg_box as *mut u8,
        args,
        (callable + abi::ROC_ERASED_CALLABLE_CAPTURE_OFFSET) as *mut u8,
        core::ptr::null_mut(), // no allocation handed over for reuse
    );
    msg_box
}

/// Dispatch a value-carrying event: call the boxed `Str -> Box(Msg)` decoder
/// at `callable` with the string JS wrote at (`val_ptr`, `val_len`) via
/// `js_alloc`, then run `update` with the resulting message box.
#[no_mangle]
pub extern "C" fn dispatch_value(callable: usize, val_ptr: usize, val_len: usize) -> u32 {
    unsafe {
        let value = str_from_parts(val_ptr, val_len);
        // The callable consumes its args (the string moves into the msg).
        let msg_box = call_callable(callable, &raw const value as *const u8);
        run_update(msg_box)
    }
}

/// One extra reference to a `str_from_parts` string: small strings live
/// inline (the struct copy IS the reference), heap strings bump the block's
/// refcount. The small-string marker is the top bit of the length word.
unsafe fn str_incref(s: &RocStr) {
    if s.length & (isize::MIN as usize) == 0 {
        incref(s.bytes as usize);
    }
}

/// The `KeyEvent` record for a key dispatch; `flags` packs the booleans
/// (1 ctrl, 2 shift, 4 alt, 8 meta, 16 repeat, 32 is_composing, mirrored
/// in the runtime's keyFlags).
fn key_event_args(key: RocStr, code: RocStr, flags: u32) -> KeyArgs {
    KeyArgs {
        key,
        code,
        ctrl: flags & 1 != 0,
        shift: flags & 2 != 0,
        alt: flags & 4 != 0,
        meta: flags & 8 != 0,
        repeat: flags & 16 != 0,
        is_composing: flags & 32 != 0,
    }
}

/// Dispatch an element-level keyboard event: call the boxed
/// `KeyEvent -> Box(Msg)` decoder with the record built from what JS wrote
/// via `js_alloc`, then run `update` with the resulting message box.
#[no_mangle]
pub extern "C" fn dispatch_key(
    callable: usize,
    key_ptr: usize,
    key_len: usize,
    code_ptr: usize,
    code_len: usize,
    flags: u32,
) -> u32 {
    unsafe {
        let args = key_event_args(
            str_from_parts(key_ptr, key_len),
            str_from_parts(code_ptr, code_len),
            flags,
        );
        // The callable consumes its args (the strings move into the msg).
        let msg_box = call_callable(callable, &raw const args as *const u8);
        run_update(msg_box)
    }
}

/// Dispatch an element-level pointer event: build the `PointerEvent` record
/// from what JS passes (coordinates as f64, button/buttons, and the same
/// packed modifier flags as key events: 1 ctrl, 2 shift, 4 alt, 8 meta),
/// call the boxed `PointerEvent -> Box(Msg)` decoder, then run `update`.
#[no_mangle]
pub extern "C" fn dispatch_pointer(
    callable: usize,
    client_x: f64,
    client_y: f64,
    page_x: f64,
    page_y: f64,
    offset_x: f64,
    offset_y: f64,
    button: u32,
    buttons: u32,
    flags: u32,
) -> u32 {
    unsafe {
        let args = PointerArgs {
            client_x,
            client_y,
            offset_x,
            offset_y,
            page_x,
            page_y,
            alt: flags & 4 != 0,
            button: button as u8,
            buttons: buttons as u8,
            ctrl: flags & 1 != 0,
            meta: flags & 8 != 0,
            shift: flags & 2 != 0,
        };
        let msg_box = call_callable(callable, &raw const args as *const u8);
        run_update(msg_box)
    }
}

/// Dispatch a file input's selection: build the `FileInfo` record from what
/// JS wrote via `js_alloc` (name and mime strings) and passes by value (the
/// id it minted for the File object, and the size as an f64, exact for any
/// real file size), call the boxed `FileInfo -> Box(Msg)` decoder, then run
/// `update`.
#[no_mangle]
pub extern "C" fn dispatch_file(
    callable: usize,
    id: u32,
    name_ptr: usize,
    name_len: usize,
    mime_ptr: usize,
    mime_len: usize,
    size: f64,
) -> u32 {
    unsafe {
        let args = FileArgs {
            size: size as u64,
            mime: str_from_parts(mime_ptr, mime_len),
            name: str_from_parts(name_ptr, name_len),
            id,
        };
        // The callable consumes its args (the strings move into the msg).
        let msg_box = call_callable(callable, &raw const args as *const u8);
        run_update(msg_box)
    }
}

/// Dispatch a byte-carrying one-shot response (a crypto digest's hash): JS
/// wrote the bytes via `js_alloc`; call the boxed `List(U8) -> Box(Msg)`
/// callback, then run `update`. Empty bytes signal failure (see Crypto).
/// One-shot: releases the reference JS held.
#[no_mangle]
pub extern "C" fn dispatch_bytes(callable: usize, ptr: usize, len: usize) -> u32 {
    unsafe {
        let args = abi::RocListWith::<u8, false> {
            elements: ptr as *mut u8,
            length: len,
            // Same capacity encoding as dispatch_http's body list.
            capacity_or_alloc_ptr: len << 1,
        };
        // The callable consumes its args (the list moves into the msg).
        let msg_box = call_callable(callable, &raw const args as *const u8);
        let changed = run_update(msg_box);
        abi::roc_drop_bytes_callback(callable as abi::RocErasedCallable);
        changed
    }
}

/// Release a timer callback JS holds without dispatching it: a debounce that
/// was re-armed (the fresh effect carries a fresh callback) or canceled
/// (`Time.cancel`) before firing.
#[no_mangle]
pub extern "C" fn drop_timer_cb(callable: usize) {
    unsafe { abi::roc_drop_timer_callback(callable as abi::RocErasedCallable) }
}

/// The u32 at `off` regardless of alignment: the packed header buffer
/// interleaves length words with raw string bytes.
#[inline]
unsafe fn read_u32_unaligned(off: usize) -> u32 {
    core::ptr::read_unaligned(off as *const u32)
}

/// Build the response-header `List({ name : Str, value : Str })` from the
/// packed buffer JS wrote via `js_alloc`: a u32 count, then per header a u32
/// byte length + UTF-8 bytes for the name and the same for the value. The
/// strings are copied into refcounted allocations Roc owns (freed with the
/// response record), the packed buffer itself is scratch and freed here.
/// `ptr` 0 means no headers.
unsafe fn headers_from_packed(ptr: usize) -> abi::RocList<HeaderPair> {
    let empty = abi::RocList {
        elements: core::ptr::null_mut(),
        length: 0,
        capacity_or_alloc_ptr: 0,
    };
    if ptr == 0 {
        return empty;
    }
    let count = read_u32_unaligned(ptr) as usize;
    if count == 0 {
        roc_dealloc((ptr - 4) as *mut u8, 4);
        return empty;
    }
    let block = roc_alloc(4 + count * HEADER_STRIDE, 4) as usize;
    if block == 0 {
        core::arch::wasm32::unreachable();
    }
    *(block as *mut isize) = 1; // refcount: owned; Roc frees the list
    let elements = (block + 4) as *mut HeaderPair;
    let mut at = ptr + 4;
    for i in 0..count {
        let name_len = read_u32_unaligned(at) as usize;
        let name = str_copied(at + 4, name_len);
        at += 4 + name_len;
        let value_len = read_u32_unaligned(at) as usize;
        let value = str_copied(at + 4, value_len);
        at += 4 + value_len;
        core::ptr::write(elements.add(i), HeaderPair { name, value });
    }
    roc_dealloc((ptr - 4) as *mut u8, 4); // the packed buffer is scratch
    abi::RocList {
        elements,
        length: count,
        capacity_or_alloc_ptr: count << 1,
    }
}

/// Dispatch an HTTP response: JS wrote the body bytes and the packed header
/// buffer via `js_alloc`; build the response record, call the boxed callback,
/// then run `update`. Statuses 0 (never completed) and 1 (timed out) are the
/// transport sentinels the Http module decodes, real statuses start at 100.
#[no_mangle]
pub extern "C" fn dispatch_http(
    callable: usize,
    status: u32,
    body_ptr: usize,
    body_len: usize,
    headers_ptr: usize,
) -> u32 {
    unsafe {
        let args = HttpArgs {
            body: abi::RocListWith {
                elements: body_ptr as *mut u8,
                length: body_len,
                // Lists share the string capacity encoding: capacity is stored
                // shifted left one bit (low bit = seamless-slice tag, 0 here),
                // so the decoded capacity is `body_len`.
                capacity_or_alloc_ptr: body_len << 1,
            },
            headers: headers_from_packed(headers_ptr),
            status: status as u16,
        };
        // The callable consumes its args (the body list moves into the msg).
        let msg_box = call_callable(callable, &raw const args as *const u8);
        let changed = run_update(msg_box);
        // HTTP responses are one-shot: release the reference JS held.
        abi::roc_drop_http_callback(callable as abi::RocErasedCallable);
        changed
    }
}

/// Dispatch a timer firing: call the boxed `I64 -> Box(Msg)` callback with the
/// current time (ms since epoch, passed from JS as an f64), then run
/// `update`. `one_shot` is 1 for Time.after (JS releases its reference after
/// this single firing) and 0 for Time.every (the interval keeps firing).
#[no_mangle]
pub extern "C" fn dispatch_timer(callable: usize, now_ms: f64, one_shot: u32) -> u32 {
    unsafe {
        let args: i64 = now_ms as i64;
        let msg_box = call_callable(callable, &raw const args as *const u8);
        let changed = run_update(msg_box);
        if one_shot != 0 {
            abi::roc_drop_timer_callback(callable as abi::RocErasedCallable);
        }
        changed
    }
}

// --- Console log queue ---
// The linked module is import-free: the host cannot call into JS. Messages
// queue up here as (ptr, len, level) triples and the JS runtime drains them
// after every entry call (start/dispatch/dispatch_value). Two levels feed
// the queue: LOG_LEVEL_LOG entries come from the ConsoleLog effect and go
// to `console.log`, LOG_LEVEL_DBG entries come from the compiler's `dbg`
// statement (via `roc_dbg`) and go to `console.debug`.
static mut LOG_PTR: usize = 0; // heap buffer of (ptr, len, level) triples
static mut LOG_CAP: usize = 0;
static mut LOG_LEN: usize = 0; // number of u32 words used

const LOG_LEVEL_LOG: u32 = 0;
const LOG_LEVEL_DBG: u32 = 1;

/// Copy `len` bytes at `ptr` into a host-owned block and queue it for the
/// runtime's next console drain (`log_clear` frees the copy).
unsafe fn log_push_copy(ptr: *const u8, len: usize, level: u32) {
    let copy = roc_alloc(len, 1);
    if copy.is_null() {
        core::arch::wasm32::unreachable();
    }
    core::ptr::copy_nonoverlapping(ptr, copy, len);
    buf_push(&mut LOG_PTR, &mut LOG_CAP, &mut LOG_LEN, LOG_INITIAL, copy as u32);
    buf_push(&mut LOG_PTR, &mut LOG_CAP, &mut LOG_LEN, LOG_INITIAL, len as u32);
    buf_push(&mut LOG_PTR, &mut LOG_CAP, &mut LOG_LEN, LOG_INITIAL, level);
}

#[no_mangle]
pub extern "C" fn log_ptr() -> usize {
    unsafe { LOG_PTR }
}

#[no_mangle]
pub extern "C" fn log_len() -> usize {
    unsafe { LOG_LEN }
}

#[no_mangle]
pub extern "C" fn log_clear() {
    unsafe {
        // The queued messages are host-owned copies; free them now that JS
        // has decoded them.
        let mut i = 0;
        while i + 2 < LOG_LEN {
            let ptr = *((LOG_PTR + i * 4) as *const u32) as usize;
            if ptr != 0 {
                roc_dealloc(ptr as *mut u8, 1);
            }
            i += 3;
        }
        LOG_LEN = 0;
    }
}

#[no_mangle]
pub extern "C" fn cmd_ptr() -> usize {
    unsafe { CMDS_PTR }
}

/// Number of u32 words in the command buffer.
#[no_mangle]
pub extern "C" fn cmd_len() -> usize {
    unsafe { CMD_LEN }
}

// --- compiler-rt intrinsics ---
// Roc's builtins use 128-bit arithmetic (JSON number parsing among others)
// and LLVM lowers that to compiler-rt libcalls. A Zig host gets these from
// Zig's compiler-rt automatically, but our single-object rustc host does
// not. Bundling compiler-rt is not an option either: roc's wasm linker
// currently rejects the relocations in rustc-built .a archives, another
// known compiler bug. So the ones Roc needs are implemented here by hand. wasm32 C ABI: i128 crosses as two i64 halves,
// low first, and an i128 return becomes a leading sret pointer.

/// 128-bit multiplication: writes a * b to `ret` (two u64 words, low first).
#[no_mangle]
pub extern "C" fn __multi3(ret: *mut u64, a_lo: u64, a_hi: u64, b_lo: u64, b_hi: u64) {
    let (lo, carry) = mul_u64_wide(a_lo, b_lo);
    let hi = carry
        .wrapping_add(a_lo.wrapping_mul(b_hi))
        .wrapping_add(a_hi.wrapping_mul(b_lo));
    unsafe {
        *ret = lo;
        *ret.add(1) = hi;
    }
}

/// Full 64x64 -> 128 multiplication via 32-bit limbs, avoiding u128 (which
/// would lower right back into a __multi3 call).
fn mul_u64_wide(a: u64, b: u64) -> (u64, u64) {
    let a_lo = a & 0xffff_ffff;
    let a_hi = a >> 32;
    let b_lo = b & 0xffff_ffff;
    let b_hi = b >> 32;
    let ll = a_lo * b_lo;
    let lh = a_lo * b_hi;
    let hl = a_hi * b_lo;
    let hh = a_hi * b_hi;
    let mid = (ll >> 32) + (lh & 0xffff_ffff) + (hl & 0xffff_ffff);
    let lo = (ll & 0xffff_ffff) | (mid << 32);
    let hi = hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
    (lo, hi)
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
