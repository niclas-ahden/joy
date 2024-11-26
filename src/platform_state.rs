use std::cell::RefCell;

thread_local! {
    static MODEL: RefCell<Option<crate::glue::PlatformState>> = const { RefCell::new(None) };
}

pub fn with<T>(f: impl FnOnce(&mut Option<crate::glue::PlatformState>) -> T) -> T {
    MODEL.with_borrow_mut(|pdom| f(pdom))
}
