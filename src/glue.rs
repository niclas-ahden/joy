use roc_std::{roc_refcounted_noop_impl, RocBox, RocRefcounted};
use std::collections::HashMap;

#[repr(C)]
pub struct Return {
    pub elem: Elem,
    pub model: RocBox<()>,
}

impl roc_std::RocRefcounted for Return {
    fn inc(&mut self) {
        self.elem.inc();
        self.model.inc();
    }
    fn dec(&mut self) {
        self.elem.dec();
        self.model.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(transparent)]
pub struct ElemDiv {
    pub data: Elem,
}

impl roc_std::RocRefcounted for ElemDiv {
    fn inc(&mut self) {
        self.data.inc();
    }
    fn dec(&mut self) {
        self.data.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(transparent)]
pub struct ElemText {
    pub str: roc_std::RocStr,
}

impl roc_std::RocRefcounted for ElemText {
    fn inc(&mut self) {
        self.str.inc();
    }
    fn dec(&mut self) {
        self.str.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantElem {
    Div = 0,
    Text = 1,
}

roc_refcounted_noop_impl!(DiscriminantElem);

#[repr(transparent)]
pub struct Elem(*mut UnionElem);

impl Elem {
    pub fn discriminant(&self) -> DiscriminantElem {
        let discriminants = {
            use DiscriminantElem::*;

            [Div, Text]
        };

        if self.0.is_null() {
            unreachable!("this pointer cannot be NULL")
        } else {
            match std::mem::size_of::<usize>() {
                4 => discriminants[self.0 as usize & 0b011],
                8 => discriminants[self.0 as usize & 0b111],
                _ => unreachable!(),
            }
        }
    }

    fn unmasked_pointer(&self) -> *mut UnionElem {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut UnionElem
    }

    unsafe fn ptr_read_union(&self) -> core::mem::ManuallyDrop<UnionElem> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }
}

#[repr(C)]
union UnionElem {
    div: core::mem::ManuallyDrop<ElemDiv>,
    text: core::mem::ManuallyDrop<ElemText>,
}

impl roc_std::RocRefcounted for Elem {
    fn inc(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    let mut union = self.ptr_read_union();
                    (*union.div).inc();
                }
                DiscriminantElem::Text => {
                    let mut union = self.ptr_read_union();
                    (*union.text).inc();
                }
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    let mut union = self.ptr_read_union();
                    (*union.div).dec();
                }
                DiscriminantElem::Text => {
                    let mut union = self.ptr_read_union();
                    (*union.text).dec();
                }
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl std::fmt::Display for Elem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    write!(f, "Div ")?;

                    // write content of Div
                    let union = self.ptr_read_union();
                    write!(f, "{}", (*union.div).data)
                }
                DiscriminantElem::Text => {
                    let union = self.ptr_read_union();
                    write!(f, "{}", (*union.text).str.as_str())
                }
            }
        }
    }
}

impl From<&Elem> for percy_dom::VirtualNode {
    fn from(value: &Elem) -> percy_dom::VirtualNode {
        unsafe {
            match value.discriminant() {
                DiscriminantElem::Div => {
                    let children = vec![percy_dom::VirtualNode::from(
                        &(*value.ptr_read_union().div).data,
                    )];

                    percy_dom::VirtualNode::Element(percy_dom::VElement {
                        tag: "div".to_string(),
                        attrs: HashMap::default(),
                        events: percy_dom::event::Events::new(),
                        children,
                        special_attributes: percy_dom::SpecialAttributes::default(),
                    })
                }
                DiscriminantElem::Text => percy_dom::VirtualNode::Text(percy_dom::VText {
                    text: (*value.ptr_read_union().text).str.as_str().to_string(),
                }),
            }
        }
    }
}
