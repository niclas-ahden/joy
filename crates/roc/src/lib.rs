use roc_std::{RocBox, RocList, RocStr};
use std::alloc::{GlobalAlloc, Layout};
use std::os::raw::c_void;

pub mod glue;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let layout = Layout::from_size_align(size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.alloc(layout) as *mut c_void
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut u8, _alignment: u32) {
    let layout =
        Layout::from_size_align(0, 8).unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.dealloc(c_ptr, layout);
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
    let layout = Layout::from_size_align(old_size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.realloc(c_ptr, layout, new_size)
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

    unsafe {
        debug_assert_eq!(std::mem::size_of::<RocBox<()>>(), size() as usize);
        caller(flags)
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

    unsafe {
        debug_assert_eq!(std::mem::size_of::<glue::RawAction>(), size() as usize);
        caller(state, raw_event, payload)
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
