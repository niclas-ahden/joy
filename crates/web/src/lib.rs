use roc_std::{RocList, RocRefcounted, RocStr};
use std::collections::HashMap;
use wasm_bindgen::prelude::*;
use web_sys::Document;

mod console;
mod model;
mod pdom;

fn document() -> Option<Document> {
    web_sys::window().expect("should have a window").document()
}

// #[wasm_bindgen]
// pub fn app_update() {
//     let new_vnode: percy_dom::VirtualNode = MODEL.with_borrow_mut(|maybe_state| {
//         if let Some(model) = maybe_state {
//             let roc_return = roc_render(model.to_owned());

//             *maybe_state = Some(roc_return.model);

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
        let mut boxed_model = roc::roc_init();

        boxed_model.inc();

        // Str.toUtf8 "UserClickedText"
        let event_bytes = [
            85, 115, 101, 114, 67, 108, 105, 99, 107, 101, 100, 84, 101, 120, 116,
        ];

        let mut action = roc::roc_update(boxed_model.clone(), &mut event_bytes.into());

        assert_eq!(action.discriminant(), roc::glue::DiscriminantAction::Update);

        dbg!(&action);

        let roc_html = roc::roc_render(action.unwrap_model());

        // EXPECT CLICKED
        dbg!(&roc_html);

        *maybe_model = Some(boxed_model);

        roc_html_to_percy(&roc_html)
    });

    let app_node = document().unwrap().get_element_by_id("app").unwrap();

    pdom::set(percy_dom::PercyDom::new_replace_mount(
        initial_vnode,
        app_node,
    ));
}

/// not used
#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    console::log(msg.as_str());
}

fn roc_html_to_percy(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    match value.discriminant() {
        roc::glue::DiscriminantHtml::None => percy_dom::VirtualNode::text(""),
        roc::glue::DiscriminantHtml::Text => roc_to_percy_text_node(value),
        roc::glue::DiscriminantHtml::Element => unsafe {
            let children: Vec<percy_dom::VirtualNode> = value
                .ptr_read_union()
                .element
                .children
                .into_iter()
                .map(roc_html_to_percy)
                .collect();

            let tag = value.ptr_read_union().element.data.tag.as_str().to_owned();

            let attrs = roc_to_percy_attrs(&value.ptr_read_union().element.data.attrs);

            console::log(
                format!("EVENTS: {:?}", value.ptr_read_union().element.data.events).as_str(),
            );

            let mut events = percy_dom::event::Events::new();

            let callback = |raw_event: RocList<u8>| {
                let event_data = raw_event.clone(); // Clone the event data before moving into closure
                std::rc::Rc::new(std::cell::RefCell::new(
                    move |event: percy_dom::event::MouseEvent| {
                        console::log(
                            format!("Mouse event received! {}", event.to_string()).as_str(),
                        );

                        model::with(|maybe_model| {
                            if let Some(state) = maybe_model {

                                // let mut action = roc_update(state, event_data.clone());

                                // console::log("AFTER UPDATE");

                                // match action.discriminant() {
                                //     glue::DiscriminantAction::None => {
                                //         // no action to take
                                //     }
                                //     glue::DiscriminantAction::Update => {
                                //         // we have a new model
                                //         // model::with(|maybe_model| {
                                //         //     *maybe_model =
                                //         //         Some(action.get_model_for_update_variant());
                                //         // })
                                //     }
                                // }
                            } else {
                                // no model available... what does this mean?
                                panic!("NO MODEL AVAILABLE")
                            }
                        })
                    },
                ))
            };

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
