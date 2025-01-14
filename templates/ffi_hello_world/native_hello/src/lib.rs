use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
};

#[no_mangle]
pub extern "C" fn greet_human_ffi(name: *const c_char) -> *const c_char {
    let name_str = unsafe { CStr::from_ptr(name) };
    let greeting = format!("Hello, {}!", name_str.to_str().unwrap());
    let c_greeting = CString::new(greeting).expect("CString::new failed");
    c_greeting.into_raw()
}
