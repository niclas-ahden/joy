use roc_std::RocStr;
use std::alloc::GlobalAlloc;
use std::alloc::Layout;
use std::os::raw::c_void;
use wasm_bindgen::prelude::*;
use wee_alloc;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

#[wasm_bindgen(start)]
fn run() -> Result<(), JsValue> {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    let window = web_sys::window().expect("no global `window` exists");
    let document = window.document().expect("should have a document on window");
    let body = document.body().expect("document should have a body");

    let msg = call_roc();

    let val = document.create_element("p")?;
    val.set_text_content(Some(msg.as_str()));

    body.append_child(&val)?;

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

pub fn call_roc() -> String {
    #[link(name = "app")]
    extern "C" {
        #[link_name = "roc__mainForHost_1_exposed"]
        fn main_for_host(arg_not_used: i32) -> RocStr;
    }

    let roc_str = unsafe { main_for_host(0) };

    roc_str.as_str().to_owned()
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    let msg: wasm_bindgen::JsValue = msg.as_str().into();
    web_sys::console::log_1(&msg);
}
