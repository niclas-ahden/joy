use wasm_bindgen::prelude::*;

mod roc;

#[wasm_bindgen(start)]
fn run() -> Result<(), JsValue> {
    let window = web_sys::window().expect("no global `window` exists");
    let document = window.document().expect("should have a document on window");
    let body = document.body().expect("document should have a body");

    let msg = roc::call_roc();

    let val = document.create_element("p")?;
    val.set_text_content(Some(msg.as_str()));

    body.append_child(&val)?;

    Ok(())
}
