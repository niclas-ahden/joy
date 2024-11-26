use roc_std::{RocBox, RocStr};
use std::alloc::GlobalAlloc;
use std::alloc::Layout;
use std::os::raw::c_void;
use wasm_bindgen::prelude::*;
use web_sys::Document;

mod console;
mod glue;
mod model;
mod pdom;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

fn document() -> Option<Document> {
    web_sys::window().expect("should have a window").document()
}

// #[wasm_bindgen]
// pub fn app_update() {
//     let new_vnode: percy_dom::VirtualNode = MODEL.with_borrow_mut(|maybe_model| {
//         if let Some(model) = maybe_model {
//             let roc_return = roc_render(model.to_owned());

//             *maybe_model = Some(roc_return.model);

//             (&roc_return.elem).into()
//         } else {
//             percy_dom::VirtualNode::text("Loading...")
//         }
//     });

//     with_pdom(|pdom| {
//         pdom.update(new_vnode);
//     });
// }

#[wasm_bindgen]
pub fn app_init() {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    console::log("INFO: STARTING APP");

    let initial_vnode = model::with(|maybe_model| {
        let platform_state = roc_init();

        let platform_state = roc_render(platform_state.boxed_model);

        let initial_vnode = (&platform_state.html_with_handler_ids).into();

        *maybe_model = Some(platform_state);

        initial_vnode
    });

    let app_node = document().unwrap().get_element_by_id("app").unwrap();

    pdom::set(percy_dom::PercyDom::new_replace_mount(
        initial_vnode,
        app_node,
    ));
}

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

pub fn roc_init() -> glue::PlatformState {
    #[link(name = "app")]
    extern "C" {
        // initForHost : I32 -> PlatformState Model
        #[link_name = "roc__initForHost_1_exposed"]
        fn caller(arg_not_used: i32) -> glue::PlatformState;
    }

    unsafe { caller(0) }
}

pub fn roc_update(state: glue::PlatformState, event_id: u64) -> glue::Action {
    #[link(name = "app")]
    extern "C" {
        // updateForHost : PlatformState Model, U64 -> Action.Action (Box Model)
        #[link_name = "roc__updateForHost_1_exposed"]
        fn caller(state: glue::PlatformState, event_id: u64) -> glue::Action;
    }

    unsafe { caller(state, event_id) }
}

pub fn roc_render(model: RocBox<()>) -> glue::PlatformState {
    #[link(name = "app")]
    extern "C" {
        // renderForHost : Box Model -> PlatformState Model
        #[link_name = "roc__renderForHost_1_exposed"]
        fn caller(model: RocBox<()>) -> glue::PlatformState;
    }

    unsafe { caller(model) }
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    console::log(msg.as_str());
}
