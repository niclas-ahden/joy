use roc_std::RocList;
use roc_std::RocStr;
use std::collections::HashMap;
use wasm_bindgen::prelude::*;

mod console;
mod model;
mod pdom;

#[wasm_bindgen]
pub fn run(flags: String) {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));
    // console::log(&format!("Starting app..."));

    let initial_vnode = model::with(|maybe_model| {
        // call into roc to get the initial model
        let boxed_model = roc::roc_init(&flags.as_str().into());

        // save the model for later
        *maybe_model = Some(boxed_model.clone());

        // render the model to html
        let roc_html = roc::roc_render(boxed_model);

        // convert the roc html to percy virtual node
        roc_html_to_percy(&roc_html)
    });

    let app_node = web_sys::window()
        .expect("should have a browser window")
        .document()
        .unwrap()
        .get_element_by_id("app")
        .unwrap();

    pdom::set(percy_dom::PercyDom::new_replace_mount(
        initial_vnode,
        app_node,
    ));
}

#[wasm_bindgen]
pub fn port(event: String) {
    // console::log(&format!("Port received event: {event}"));
    roc_run_event(&event.as_str().into(), &("".into()))
}

fn roc_html_to_percy(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    match value.discriminant() {
        roc::glue::DiscriminantHtml::None => percy_dom::VirtualNode::text(""),
        roc::glue::DiscriminantHtml::Text => roc_to_percy_text_node(value),
        roc::glue::DiscriminantHtml::Element => unsafe {
            // convert all the children to percy virtual nodes
            let children: Vec<percy_dom::VirtualNode> = value
                .ptr_read_union()
                .element
                .children
                .into_iter()
                .map(roc_html_to_percy)
                .collect();

            let tag = value.ptr_read_union().element.data.tag.as_str().to_owned();
            let attrs = roc_to_percy_attrs(&value.ptr_read_union().element.data.attrs);
            let mut events = percy_dom::event::Events::new();

            // TODO: Support more event types
            let mouse_event_callback = |raw_event: RocStr| {
                std::rc::Rc::new(std::cell::RefCell::new(
                    move |_event: percy_dom::event::MouseEvent| {
                        roc_run_event(&raw_event, &("".into()))
                    },
                ))
            };
            let input_event_callback = |raw_event: RocStr| {
                let tag = tag.clone();
                std::rc::Rc::new(Closure::<dyn FnMut(web_sys::InputEvent)>::new(
                    move |e: web_sys::InputEvent| {
                        fn current_target<T>(event: web_sys::InputEvent) -> T
                        where
                            T: wasm_bindgen::JsCast,
                        {
                            event
                                .current_target()
                                .expect("must have a `current_target`")
                                .dyn_into::<T>()
                                .expect("failed to cast `current_target` into element type {T:?}")
                        }

                        // TODO: Should we support arbitrary elements with `contenteditable` or
                        // `designMode`?
                        let current_target_value = match tag.as_str() {
                            "input" => current_target::<web_sys::HtmlInputElement>(e).value(),
                            "textarea" => current_target::<web_sys::HtmlTextAreaElement>(e).value(),
                            "select" => current_target::<web_sys::HtmlSelectElement>(e).value(),
                            _ => panic!("Unsupported tag type for `InputEvent`: {tag}"),
                        };

                        roc_run_event(&raw_event, &(current_target_value.as_str().into()))
                    },
                ))
            };

            for event in value.ptr_read_union().element.data.events.into_iter() {
                let event_name = event.name.to_string();
                match event_name.as_str() {
                    "onclick" => events.insert_mouse_event(
                        event_name.into(),
                        mouse_event_callback(event.handler.clone()),
                    ),
                    "oninput" => events.__insert_unsupported_signature(
                        event_name.into(),
                        input_event_callback(event.handler.clone()),
                    ),
                    event_name => panic!("Unsupported event type: {event_name}"),
                }
            }

            percy_dom::VirtualNode::Element(percy_dom::VElement {
                tag,
                attrs,
                events,
                children,
                special_attributes: percy_dom::SpecialAttributes::default(),
            })
        },
    }
}

fn roc_run_event(roc_event: &RocStr, event_payload: &RocStr) {
    model::with(|maybe_model| {
        if let Some(boxed_model) = maybe_model {
            let mut action = roc::roc_update(boxed_model.clone(), roc_event, event_payload);

            match action.discriminant() {
                roc::glue::DiscriminantAction::None => {
                    // no action to take
                }
                roc::glue::DiscriminantAction::Update => {
                    // we have a new model
                    let new_model = action.unwrap_model();

                    pdom::with(|pdom| {
                        // pass the new model to roc to render the new html
                        let new_html = roc::roc_render(new_model.clone());

                        // convert the new roc html to percy virtual node
                        let new_vnode = roc_html_to_percy(&new_html);

                        // diff and patch the DOM
                        pdom.update(new_vnode);
                    });

                    // save the new model for later
                    *maybe_model = Some(new_model);
                }
            }
        } else {
            // no model available... what does this mean?
            // might be relevant when we support more events
            panic!("NO MODEL AVAILABLE")
        }
    })
}

fn roc_to_percy_text_node(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    unsafe { percy_dom::VirtualNode::text(value.ptr_read_union().text.str.as_str()) }
}

pub fn roc_to_percy_attrs(
    values: &RocList<roc::glue::ElementAttrs>,
) -> HashMap<String, percy_dom::AttributeValue> {
    HashMap::from_iter(
        values.into_iter().filter_map(|attr| {
            let key = attr.key.as_str();
            let value = match key {
                // TODO: Preferably we wouldn't have to maintain a list of all attributes
                // where `percy-dom` expects a bool instead of a string.
                "checked" | "disabled" => match attr.val.as_str() {
                    "true" => percy_dom::AttributeValue::Bool(true),
                    "false" => percy_dom::AttributeValue::Bool(false),
                    non_bool => panic!("Unexpected value for attribute \"{key}\". Expected \"true\" or \"false\", got: \"{non_bool}\""),
                },

                // NOTE: The list of boolean attributes must be kept in sync with `joy-html`'s list
                // in `Attribute.roc`.
                "allowfullscreen" | "alpha" | "async" | "autofocus" | "autoplay" | "controls" | "default" | "defer" | "formnovalidate" | "inert" | "ismap" | "itemscope" | "loop" | "multiple" | "muted" | "nomodule" | "novalidate" | "open" | "playsinline" | "readonly" | "required" | "reversed" | "selected" | "shadowrootclonable" | "shadowrootdelegatesfocus" | "shadowrootserializable" => match attr.val.as_str() {
                    "true" => percy_dom::AttributeValue::String("".to_string()),
                    "false" => return None,
                    non_bool => panic!("Unexpected value for attribute \"{key}\". Expected \"true\" or \"false\", got: \"{non_bool}\""),
                },
                _ => percy_dom::AttributeValue::String(attr.val.as_str().to_string()),
            };

            Some((key.to_string(), value))
        })
    )
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    let msg: wasm_bindgen::JsValue = msg.as_str().into();
    web_sys::console::log_1(&msg);
}

#[no_mangle]
pub extern "C" fn roc_fx_get(url: &RocStr, raw_event: &RocStr) {
    let url_ = url.to_string();
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let body_or_error = match reqwest::get(url_).await {
            Ok(response) => response.text().await,
            Err(e) => Err(e),
        }
        .map_err(|e| e.to_string())
        .unwrap_or_else(|e| e);

        // TODO: Return a fitting type such as `RocResult HttpResponse HttpError` (or
        // perhaps `RocResult String HttpError` for this `get!` function and the more
        // specific `HttpResponse` for a more general `request!` function).
        roc_run_event(&raw_event_, &(body_or_error.as_str().into()))
    });
}
