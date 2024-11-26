use percy_dom::PercyDom;
use roc_std::{RocBox, RocResult, RocStr};
use std::alloc::GlobalAlloc;
use std::alloc::Layout;
use std::cell::RefCell;
use std::os::raw::c_void;
use wasm_bindgen::prelude::*;
use web_sys::Document;

mod console;
mod glue;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

thread_local! {
    static PDOM: RefCell<Option<PercyDom>> = const { RefCell::new(None) };
    static MODEL: RefCell<Option<Model>> = const { RefCell::new(None) };
}

fn document() -> Option<Document> {
    web_sys::window().expect("should have a window").document()
}

fn with_pdom(f: impl FnOnce(&mut PercyDom)) {
    PDOM.with_borrow_mut(|pdom| {
        if let Some(dom) = pdom {
            f(dom);
        }
    });
}

fn set_pdom(new_pdom: PercyDom) {
    PDOM.with_borrow_mut(|pdom| {
        *pdom = Some(new_pdom);
    });
}

#[wasm_bindgen]
pub fn app_update() {
    let new_vnode: percy_dom::VirtualNode = MODEL.with_borrow_mut(|maybe_model| {
        if let Some(model) = maybe_model {
            let roc_return = roc_render(model.to_owned());

            *maybe_model = Some(roc_return.model);

            (&roc_return.elem).into()
        } else {
            percy_dom::VirtualNode::text("Loading...")
        }
    });

    with_pdom(|pdom| {
        pdom.update(new_vnode);
    });
}

#[wasm_bindgen]
pub fn app_init() {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    console::log("INFO: STARTING APP");

    let initial_vnode = MODEL.with_borrow_mut(|maybe_model| {
        let roc_return = roc_render(roc_init());

        *maybe_model = Some(roc_return.model);

        (&roc_return.elem).into()
    });

    let app_node = document().unwrap().get_element_by_id("app").unwrap();

    set_pdom(percy_dom::PercyDom::new_replace_mount(
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

type Model = RocBox<()>;

pub fn roc_init() -> Model {
    #[link(name = "app")]
    extern "C" {
        #[link_name = "roc__initForHost_1_exposed"]
        fn init_for_host(arg_not_used: i32) -> Model;
    }

    unsafe { init_for_host(0) }
}

pub fn roc_render(model: Model) -> glue::Return {
    #[link(name = "app")]
    extern "C" {
        #[link_name = "roc__renderForHost_1_exposed"]
        fn render_for_host(model: Model) -> glue::Return;
    }

    unsafe { render_for_host(model) }
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    console::log(msg.as_str());
}

#[no_mangle]
pub extern "C" fn roc_fx_getInnerHtml(id: &RocStr) -> RocResult<RocStr, ()> {
    match document().unwrap().get_element_by_id(id.as_str()) {
        Some(elem) => {
            let html = elem.inner_html();
            RocResult::ok(html.as_str().into())
        }
        None => RocResult::err(()),
    }
}
