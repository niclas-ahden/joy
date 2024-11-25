#![allow(non_snake_case)]
use roc_std::RocStr;
use std::alloc::{alloc, dealloc, realloc, Layout};
use std::os::raw::c_void;

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let layout = Layout::from_size_align(size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));
    alloc(layout) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    let layout =
        Layout::from_size_align(0, 8).unwrap_or_else(|_| std::panic::panic_any("invalid layout"));
    dealloc(c_ptr as *mut u8, layout);
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    let layout = Layout::from_size_align(old_size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));
    realloc(c_ptr as *mut u8, layout, new_size) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, _tag_id: u32) {
    panic!("ROC CRASHED {}", msg.as_str().to_string())
}

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
