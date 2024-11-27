use roc_std::RocList;
use std::collections::HashMap;
use wasm_bindgen::prelude::*;

mod console;
mod model;
mod pdom;

#[wasm_bindgen]
pub fn run() {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    console::log("INFO: STARTING APP...");

    let initial_vnode = model::with(|maybe_model| {
        // call into roc to get the initial model
        let boxed_model = roc::roc_init();

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

            let callback = |raw_event: RocList<u8>| {
                let event_data = raw_event.clone();
                std::rc::Rc::new(std::cell::RefCell::new(
                    move |_event: percy_dom::event::MouseEvent| {
                        model::with(|maybe_model| {
                            if let Some(boxed_model) = maybe_model {
                                let mut data = event_data.clone();
                                let mut action = roc::roc_update(boxed_model.clone(), &mut data);

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
                                // might be relevant when we support more than just "clicks"
                                panic!("NO MODEL AVAILABLE")
                            }
                        })
                    },
                ))
            };

            // TODO figure out how to handle different event types
            // for now, we only support "onclick"
            for event in value.ptr_read_union().element.data.events.into_iter() {
                let event_callback = callback(event.handler.clone());
                events.insert_mouse_event("onclick".into(), event_callback);
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

fn roc_to_percy_text_node(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    unsafe { percy_dom::VirtualNode::text(value.ptr_read_union().text.str.as_str()) }
}

pub fn roc_to_percy_attrs(
    values: &RocList<roc::glue::ElementAttrs>,
) -> HashMap<String, percy_dom::AttributeValue> {
    HashMap::from_iter(values.into_iter().map(|attr| {
        (
            attr.key.as_str().to_string(),
            percy_dom::AttributeValue::String(attr.val.as_str().to_string()),
        )
    }))
}
