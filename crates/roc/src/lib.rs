use roc_std::{RocBox, RocList, RocStr};
use std::alloc::Layout;
use std::os::raw::c_void;

pub mod glue;

// No `#[global_allocator]`: Rust/percy use the target default (dlmalloc on wasm32). Roc's
// own allocations (roc_alloc/dealloc/realloc) now ALSO use that default allocator rather
// than wee_alloc. wee_alloc never reclaims freed memory, so even though the Roc Html tree
// is now correctly freed (see glue::Html), it still grew the heap every render;
// dlmalloc coalesces and reuses, like Leptos/Dioxus.
//
// dlmalloc needs the original `Layout` on free, but Roc's roc_dealloc is given only a
// pointer + alignment (no size). We store the size in a header just before the pointer
// handed to Roc (replacing a HashMap side-table that cost a hash insert/remove per
// alloc/free): one ROC_ALIGN-sized slot, so the user pointer keeps Roc's 8-byte
// alignment, holding the user size (u32) and a magic tag (u32). The magic turns "freed a
// pointer that never came from roc_alloc" — which the side-table silently tolerated, but
// which would corrupt the heap here — into a loud debug panic / silent release leak.
// (The existing code always used 8-byte alignment for Roc allocations; we keep that so
// alloc/dealloc layouts always match.)
const ROC_ALIGN: usize = 8;
const HEADER: usize = ROC_ALIGN;
const MAGIC: u32 = 0x524f_4341; // "ROCA"

/// Layout of the whole allocation (header + user bytes), as handed to dlmalloc on both
/// alloc and free — the two must match exactly or dlmalloc asserts.
unsafe fn whole_layout(user_size: usize) -> Layout {
    let total = HEADER
        .checked_add(user_size)
        .unwrap_or_else(|| std::panic::panic_any("roc_alloc size overflow"));
    Layout::from_size_align(total, ROC_ALIGN)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"))
}

unsafe fn write_header(base: *mut u8, user_size: usize) {
    let size = u32::try_from(user_size)
        .unwrap_or_else(|_| std::panic::panic_any("roc_alloc size > u32::MAX"));
    (base as *mut u32).write(size);
    (base as *mut u32).add(1).write(MAGIC);
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let size = size.max(1);
    let base = std::alloc::alloc(whole_layout(size));
    if base.is_null() {
        return std::ptr::null_mut();
    }
    write_header(base, size);
    base.add(HEADER) as *mut c_void
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut u8, _alignment: u32) {
    if c_ptr.is_null() {
        return;
    }
    if free_with_header(c_ptr) {
        return;
    }
    // roc_std's `RocBox<()>` type-erases the boxed value, so its `dec` assumes the
    // smallest box alignment (4 on wasm32) when it computes the allocation start from
    // the contents pointer. Roc allocates boxes at the alignment of their contents, so
    // for an 8- or 16-aligned model the pointer we get here is 4 or 12 bytes past the
    // true allocation start. Recover it by looking for our header there. (The old
    // side-table allocator hit the same miscomputed pointer, missed the lookup, and
    // silently leaked every replaced model box.)
    for offset in [4_usize, 12] {
        if free_with_header(c_ptr.sub(offset)) {
            return;
        }
    }
    // Not one of ours, or a double free: leak rather than corrupt, but fail loudly in
    // debug builds.
    debug_assert!(false, "roc_dealloc: pointer has no roc_alloc header");
}

/// Free `user_ptr` if it carries our header; returns false if the magic is absent.
unsafe fn free_with_header(user_ptr: *mut u8) -> bool {
    let base = user_ptr.sub(HEADER);
    if (base as *const u32).add(1).read() != MAGIC {
        return false;
    }
    let size = (base as *const u32).read() as usize;
    // Clear the magic so a double free of this pointer hits the guard above instead of
    // handing dlmalloc the same block twice.
    (base as *mut u32).add(1).write(0);
    std::alloc::dealloc(base, whole_layout(size));
    true
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut u8,
    new_size: usize,
    old_size: usize,
    _alignment: u32,
) -> *mut u8 {
    let new_size = new_size.max(1);
    let base = c_ptr.sub(HEADER);
    if (base as *const u32).add(1).read() != MAGIC {
        // Not one of ours: we can't hand it to dlmalloc. Allocate fresh, copy what the
        // caller says was there, and leak the original (loudly in debug builds).
        debug_assert!(false, "roc_realloc: pointer has no roc_alloc header");
        let fresh = roc_alloc(new_size, _alignment) as *mut u8;
        if !fresh.is_null() {
            std::ptr::copy_nonoverlapping(c_ptr, fresh, old_size.min(new_size));
        }
        return fresh;
    }
    // Roc's `old_size` argument is redundant with the header; trust the header — it is
    // what the block was actually allocated with.
    let old = (base as *const u32).read() as usize;
    let new_base = std::alloc::realloc(base, whole_layout(old), whole_layout(new_size).size());
    if new_base.is_null() {
        return std::ptr::null_mut();
    }
    write_header(new_base, new_size);
    new_base.add(HEADER)
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, _tag_id: u32) {
    panic!("ROC CRASHED {}", msg.as_str())
}

/// Currently not used, roc doesn't include `dbg` in `roc build --no-link` but we would like it to
///
/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr) {
    eprintln!("[{}] {}", loc, msg);
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    let slice = std::slice::from_raw_parts_mut(dst as *mut u8, n);
    for byte in slice {
        *byte = c as u8;
    }
    dst
}

pub fn roc_init(flags: &RocStr) -> RocBox<()> {
    #[link(name = "app")]
    extern "C" {
        // init_for_host : Str -> Model
        #[link_name = "roc__init_for_host_1_exposed"]
        fn caller(flags: &RocStr) -> RocBox<()>;

        #[link_name = "roc__init_for_host_1_exposed_size"]
        fn size() -> i64;
    }

    // Roc's `init_for_host` *consumes* (decrements) its `Str` argument. The host passes
    // `flags` by reference and keeps ownership, so give Roc its own incremented copy and
    // forget it here. Otherwise the buffer is decremented twice -- once by Roc, once when
    // the caller drops its copy -- under-counting any seamless slices Roc retains in the
    // model.
    let flags_owned = flags.clone();
    unsafe {
        debug_assert_eq!(std::mem::size_of::<RocBox<()>>(), size() as usize);
        let result = caller(&flags_owned);
        std::mem::forget(flags_owned);
        result
    }
}

pub fn roc_update(state: RocBox<()>, raw_event: &RocStr, payload: &RocList<u8>) -> glue::RawAction {
    #[link(name = "app")]
    extern "C" {
        // update_for_host : Box Model, Str, Str -> Action.Action (Box Model)
        #[link_name = "roc__update_for_host_1_exposed"]
        fn caller(state: RocBox<()>, raw_event: &RocStr, payload: &RocList<u8>) -> glue::RawAction;

        #[link_name = "roc__update_for_host_1_exposed_size"]
        fn size() -> i64;
    }

    // Roc's `update_for_host` *consumes* (decrements) its `Str` and `List U8` arguments.
    // The host passes them by reference and keeps ownership, so hand Roc its own
    // incremented copies and forget them here. Otherwise each buffer is decremented twice
    // -- once by Roc, once when the caller drops its copy. `update!` parses the event into
    // the model as seamless slices that point back into the event buffer, so the extra
    // decrement frees that buffer while the stored model still references it: a
    // use-after-free, exposed once allocations are reused (dlmalloc).
    let raw_event_owned = raw_event.clone();
    let payload_owned = payload.clone();
    unsafe {
        debug_assert_eq!(std::mem::size_of::<glue::RawAction>(), size() as usize);
        let result = caller(state, &raw_event_owned, &payload_owned);
        std::mem::forget(raw_event_owned);
        std::mem::forget(payload_owned);
        result
    }
}

pub fn roc_render(model: RocBox<()>) -> glue::Html {
    #[link(name = "app")]
    extern "C" {
        // render_for_host : Box Model -> Html.Html Model
        #[link_name = "roc__render_for_host_1_exposed"]
        fn caller(model: RocBox<()>) -> glue::Html;

        #[link_name = "roc__render_for_host_1_exposed_size"]
        fn size() -> i64;
    }

    unsafe {
        debug_assert_eq!(std::mem::size_of::<glue::Html>(), size() as usize);
        caller(model)
    }
}
