//! Performance instrumentation for the update cycle, compiled in only under the
//! `joy_bench` feature so normal builds carry zero overhead.
//!
//! Each update records the wall-clock cost of the three phases Joy owns end-to-end
//! (mirroring the classic view/diff/patch split):
//!
//!   - `render`     — Roc executes the app's `render` function
//!   - `convert`    — `roc_html_to_percy` turns Roc html into a percy `VirtualNode`
//!   - `diff_patch` — percy diffs against the live tree and patches the real DOM
//!
//! Records are appended to `window.__joy_bench` (an array of `{render, convert,
//! diff_patch}` objects, all in milliseconds) so a Playwright driver can collect them
//! with a single `evaluate!("JSON.stringify(window.__joy_bench)")`. A human-readable
//! line is also logged to the console. Sub-millisecond resolution may be coarsened by
//! the browser to mitigate timing attacks, which is fine for tracking relative changes.

use wasm_bindgen::{JsCast, JsValue};

/// Current high-resolution timestamp in milliseconds, or `0.0` if `performance` is
/// unavailable (e.g. a non-browser host). Differences of two `now()` calls are durations.
pub fn now() -> f64 {
    web_sys::window()
        .and_then(|w| w.performance())
        .map(|p| p.now())
        .unwrap_or(0.0)
}

/// Record one phase-timing sample: append it to `window.__joy_bench` and log a line.
pub fn emit(render_ms: f64, convert_ms: f64, diff_patch_ms: f64) {
    let Some(window) = web_sys::window() else {
        return;
    };

    let record = js_sys::Object::new();
    set(&record, "render", render_ms);
    set(&record, "convert", convert_ms);
    set(&record, "diff_patch", diff_patch_ms);

    bench_array(&window).push(&record);

    web_sys::console::log_1(
        &format!("JOY_BENCH render={render_ms} convert={convert_ms} diff_patch={diff_patch_ms}")
            .into(),
    );
}

/// Get `window.__joy_bench`, creating and installing a fresh array if it is missing or
/// is not an array.
fn bench_array(window: &web_sys::Window) -> js_sys::Array {
    let key = JsValue::from_str("__joy_bench");
    match js_sys::Reflect::get(window, &key) {
        Ok(value) if value.is_instance_of::<js_sys::Array>() => value.unchecked_into(),
        _ => {
            let array = js_sys::Array::new();
            let _ = js_sys::Reflect::set(window, &key, &array);
            array
        }
    }
}

fn set(object: &js_sys::Object, key: &str, value: f64) {
    let _ = js_sys::Reflect::set(object, &JsValue::from_str(key), &JsValue::from_f64(value));
}
