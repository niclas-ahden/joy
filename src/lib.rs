use percy_dom::PercyDom;
use percy_dom::VirtualNode;
use roc_std::{RocResult, RocStr};
use std::alloc::GlobalAlloc;
use std::alloc::Layout;
use std::cell::RefCell;
use std::os::raw::c_void;
use wasm_bindgen::prelude::*;
use web_sys::Document;
use wee_alloc;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

fn document() -> Option<Document> {
    web_sys::window().expect("should have a window").document()
}

fn with_pdom(f: impl FnOnce(&mut PercyDom)) {
    thread_local! {
        // just use a random PercyDom for now, we'll replace it in init
        static APP: RefCell<PercyDom> = RefCell::new(PercyDom::new(VirtualNode::text("")));
    }

    APP.with_borrow_mut(|pdom| f(pdom));
}

#[wasm_bindgen]
pub fn update() {
    let now = web_sys::js_sys::Date::now();

    let now_str = format!("{} ms since epoch", now);

    with_pdom(|pdom| {
        pdom.update(percy_dom::VirtualNode::text(now_str.as_str()));
    });
}

#[wasm_bindgen(start)]
fn run() -> Result<(), JsValue> {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    console_log("INFO: STARTING APP");

    let text = percy_dom::VirtualNode::text("Loading...");

    let app_node = document().unwrap().get_element_by_id("app").unwrap();

    with_pdom(|pdom| {
        *pdom = percy_dom::PercyDom::new_replace_mount(text, app_node);
    });

    Ok(())
}

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let layout = Layout::from_size_align(size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.alloc(layout) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut u8, _alignment: u32) {
    let layout =
        Layout::from_size_align(0, 8).unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.dealloc(c_ptr, layout);
}

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

#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, _tag_id: u32) {
    panic!("ROC CRASHED {}", msg.as_str().to_string())
}

/// Currently not used, roc doesn't include `dbg` in `roc build --no-link` but we would like it to
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr) {
    eprintln!("[{}] {}", loc, msg);
}

#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    let slice = std::slice::from_raw_parts_mut(dst as *mut u8, n);
    for byte in slice {
        *byte = c as u8;
    }
    dst
}

pub fn call_roc() {
    #[link(name = "app")]
    extern "C" {
        #[link_name = "roc__mainForHost_1_exposed"]
        fn main_for_host(arg_not_used: i32) -> i32;
    }

    let exit_code = unsafe { main_for_host(0) };

    if exit_code != 0 {
        eprintln!("roc exited with code {}", exit_code);
    }
}

fn console_log(msg: &str) {
    let msg: wasm_bindgen::JsValue = msg.into();
    web_sys::console::log_1(&msg);
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    console_log(msg.as_str());
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
