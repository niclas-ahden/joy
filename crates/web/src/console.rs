#[allow(dead_code)]
pub fn log(msg: &str) {
    let msg: wasm_bindgen::JsValue = msg.into();
    web_sys::console::log_1(&msg);
}
