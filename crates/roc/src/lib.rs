use roc_std::{RocList, RocRefcounted, RocStr};
use std::alloc::{GlobalAlloc, Layout};
use std::os::raw::c_void;

mod glue;

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

pub fn roc_init() -> glue::Model {
    #[link(name = "app")]
    extern "C" {
        // initForHost : I32 -> Model
        #[link_name = "roc__initForHost_1_exposed"]
        fn caller(arg_not_used: i32) -> glue::Model;
    }

    unsafe { caller(0) }
}

pub fn roc_update(state: &mut glue::Model, raw_event: &mut RocList<u8>) -> glue::RawAction {
    #[link(name = "app")]
    extern "C" {
        // updateForHost : Box Model, List U8 -> Action.Action (Box Model)
        #[link_name = "roc__updateForHost_1_exposed"]
        fn caller(state: &mut glue::Model, raw_event: &mut RocList<u8>) -> glue::RawAction;

        #[link_name = "roc__updateForHost_1_exposed_size"]
        fn size() -> usize;
    }

    unsafe {
        assert_eq!(std::mem::size_of::<glue::RawAction>(), size());
        caller(state, raw_event)
    }
}

pub fn roc_render(model: &mut glue::Model) -> glue::Html {
    #[link(name = "app")]
    extern "C" {
        // renderForHost : Box Model -> Html.Html Model
        #[link_name = "roc__renderForHost_1_exposed"]
        fn caller(model: &mut glue::Model) -> glue::Html;
    }

    // increment refcount so roc doesn't deallocate
    model.inc();

    unsafe { caller(model) }
}
