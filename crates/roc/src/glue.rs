use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocStr};

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantAction {
    None = 0,
    Update = 1,
}

impl core::fmt::Debug for DiscriminantAction {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::None => f.write_str("Action::None"),
            Self::Update => f.write_str("Action::Update"),
        }
    }
}

roc_refcounted_noop_impl!(DiscriminantAction);

#[repr(C)]
pub struct RawAction {
    payload: [i32; 1],
    discriminant: u8,
}

const _SIZE_CHECK_ACTION: () = assert!(core::mem::size_of::<RawAction>() == 8);
const _ALIGN_CHECK_ACTION: () = assert!(core::mem::align_of::<RawAction>() == 4);

impl RawAction {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantAction {
        if self.discriminant == 0 {
            DiscriminantAction::None
        } else if self.discriminant == 1 {
            DiscriminantAction::Update
        } else {
            panic!("Unknown discriminant: {}", self.discriminant);
        }
    }

    pub fn unwrap_model(&mut self) -> RocBox<()> {
        if self.discriminant() == DiscriminantAction::Update {
            unsafe { std::mem::transmute::<[i32; 1], RocBox<()>>(self.payload) }
        } else {
            panic!("Expected Update, got {:?}", self.discriminant());
        }
    }
}

impl Drop for RawAction {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.dec(),
        }
    }
}

impl RocRefcounted for RawAction {
    fn inc(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.inc(),
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.dec(),
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl std::fmt::Debug for RawAction {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self.discriminant() {
            DiscriminantAction::None => f.debug_struct("Action::None").finish(),
            DiscriminantAction::Update => f
                .debug_struct("Action::Update")
                .field("payload", &self.payload)
                .finish(),
        }
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ElementAttrs {
    pub key: RocStr,
    pub val: RocStr,
}

impl RocRefcounted for ElementAttrs {
    fn inc(&mut self) {
        self.key.inc();
        self.val.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.val.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct EventData {
    pub handler: RocList<u8>,
    pub name: RocStr,
}

impl RocRefcounted for EventData {
    fn inc(&mut self) {
        self.name.inc();
        self.handler.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.handler.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ElementData {
    pub attrs: RocList<ElementAttrs>,
    pub events: RocList<EventData>,
    pub tag: RocStr,
}

impl RocRefcounted for ElementData {
    fn inc(&mut self) {
        self.attrs.inc();
        self.events.inc();
        self.tag.inc();
    }
    fn dec(&mut self) {
        self.attrs.dec();
        self.events.dec();
        self.tag.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone)]
#[repr(C)]
pub struct HtmlElement {
    pub data: ElementData,
    pub children: RocList<Html>,
}

impl RocRefcounted for HtmlElement {
    fn inc(&mut self) {
        self.data.inc();
        self.children.inc();
    }
    fn dec(&mut self) {
        self.data.dec();
        self.children.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(transparent)]
pub struct HtmlText {
    pub str: RocStr,
}

impl RocRefcounted for HtmlText {
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

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum DiscriminantHtml {
    Element = 0,
    None = 1,
    Text = 2,
}

roc_refcounted_noop_impl!(DiscriminantHtml);

#[repr(transparent)]
pub struct Html(*mut UnionHtml);

const _SIZE_CHECK_HTML: () = assert!(core::mem::size_of::<Html>() == 4);
const _ALIGN_CHECK_HTML: () = assert!(core::mem::align_of::<Html>() == 4);

impl Html {
    pub fn discriminant(&self) -> DiscriminantHtml {
        let discriminants = {
            use DiscriminantHtml::*;

            [Element, None, Text]
        };

        if self.0.is_null() {
            discriminants[1]
        } else {
            match std::mem::size_of::<usize>() {
                4 => discriminants[self.0 as usize & 0b011],
                8 => discriminants[self.0 as usize & 0b111],
                _ => unreachable!(),
            }
        }
    }

    fn unmasked_pointer(&self) -> *mut UnionHtml {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut UnionHtml
    }

    pub fn ptr_read_union(&self) -> core::mem::ManuallyDrop<UnionHtml> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }
}

impl std::fmt::Display for Html {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &(*ptr).element;
                    let tag = element.data.tag.as_str();

                    write!(f, "<{}>", tag)?;

                    for (i, child) in element.children.iter().enumerate() {
                        if i > 0 {
                            write!(f, " ")?;
                        }
                        write!(f, "{}", child)?;
                    }

                    write!(f, "</{}>", tag)
                }
                DiscriminantHtml::None => write!(f, "Html::None"),
                DiscriminantHtml::Text => {
                    let text = &(*ptr).text;
                    let bytes = text.str.as_str().as_bytes();
                    // Convert to ASCII string, stopping at first null byte
                    let ascii_str: String = bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| b as char)
                        .collect();
                    write!(f, "{}", ascii_str)
                }
            }
        }
    }
}

impl core::fmt::Debug for Html {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self.discriminant() {
            DiscriminantHtml::Element => {
                let payload_union = self.ptr_read_union();

                unsafe {
                    f.debug_tuple("Html::Element")
                        .field(&payload_union.element.data)
                        .field(&payload_union.element.children)
                        .finish()
                }
            }
            DiscriminantHtml::None => f.debug_tuple("Html::None").finish(),
            DiscriminantHtml::Text => {
                let payload_union = self.ptr_read_union();

                unsafe {
                    let text = &payload_union.text;
                    let bytes = text.str.as_str().as_bytes();
                    let safe_str: String = bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| b as char)
                        .collect();
                    f.debug_tuple("Html::Text").field(&safe_str).finish()
                }
            }
        }
    }
}

#[repr(C)]
pub union UnionHtml {
    pub element: core::mem::ManuallyDrop<HtmlElement>,
    pub none: (),
    pub text: core::mem::ManuallyDrop<HtmlText>,
}

impl RocRefcounted for Html {
    fn inc(&mut self) {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &mut (*ptr).element;
                    element.children.inc();
                    element.data.inc();
                }
                DiscriminantHtml::Text => {
                    let text = &mut (*ptr).text;
                    text.str.inc();
                }
                DiscriminantHtml::None => {}
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &mut (*ptr).element;
                    element.children.dec();
                    element.data.dec();
                }
                DiscriminantHtml::Text => {
                    let text = &mut (*ptr).text;
                    text.str.dec();
                }
                DiscriminantHtml::None => {}
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
