use percy_dom::PercyDom;
use std::cell::RefCell;

thread_local! {
    static PDOM: RefCell<Option<PercyDom>> = const { RefCell::new(None) };
}

/// PercyDom will be initialized with a VirtualNode on startup, so we can safely unwrap here.
pub fn with(f: impl FnOnce(&mut PercyDom)) {
    PDOM.with_borrow_mut(|pdom| {
        if let Some(dom) = pdom {
            f(dom);
        }
    });
}

pub fn set(new_pdom: PercyDom) {
    PDOM.with_borrow_mut(|pdom| {
        *pdom = Some(new_pdom);
    });
}
