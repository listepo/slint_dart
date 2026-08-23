#![allow(non_camel_case_types)]

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::ptr;
use std::rc::Rc;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType, PremultipliedRgbaColor};
use slint::PhysicalSize;
use slint_dart_core::{Definition, Engine, Instance};

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

fn set_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

fn clear_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = None);
}

fn get_error() -> Option<String> {
    LAST_ERROR.with(|e| e.borrow_mut().take())
}


// === Engine ===

#[repr(transparent)]
pub struct SlintNativeEngine(*mut c_void);

#[no_mangle]
pub extern "C" fn slint_native_engine_new() -> SlintNativeEngine {
    clear_error();
    match catch_unwind(|| {
        let engine = Engine::new();
        Box::into_raw(Box::new(engine)) as *mut c_void
    }) {
        Ok(ptr) => SlintNativeEngine(ptr),
        Err(_) => {
            set_error("panicked in slint_native_engine_new".into());
            SlintNativeEngine(ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_engine_free(engine: SlintNativeEngine) {
    if !engine.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(engine.0 as *mut Engine) });
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_native_engine_compile(
    engine: SlintNativeEngine,
    source: *const c_char,
    path: *const c_char,
) -> SlintNativeDefinitionList {
    clear_error();
    match catch_unwind(|| {
        if engine.0.is_null() || source.is_null() {
            set_error("null engine or source".into());
            return SlintNativeDefinitionList(ptr::null_mut());
        }

        let source_str = match unsafe { CStr::from_ptr(source) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("source is not valid UTF-8".into());
                return SlintNativeDefinitionList(ptr::null_mut());
            }
        };

        let path_str = if path.is_null() {
            "".to_string()
        } else {
            match unsafe { CStr::from_ptr(path) }.to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_error("path is not valid UTF-8".into());
                    return SlintNativeDefinitionList(ptr::null_mut());
                }
            }
        };

        let engine = unsafe { &mut *(engine.0 as *mut Engine) };
        let defs = match engine.compile(source_str, &path_str) {
            Ok(d) => d,
            Err(e) => {
                set_error(e);
                return SlintNativeDefinitionList(ptr::null_mut());
            }
        };

        let list = Box::new(defs);
        SlintNativeDefinitionList(Box::into_raw(list) as *mut c_void)
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_native_engine_compile".into());
            SlintNativeDefinitionList(ptr::null_mut())
        }
    }
}

// === Definitions ===

#[repr(transparent)]
pub struct SlintNativeDefinitionList(*mut c_void);

#[no_mangle]
pub extern "C" fn slint_native_definitions_count(list: SlintNativeDefinitionList) -> u32 {
    if list.0.is_null() {
        return 0;
    }
    match catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        defs.len() as u32
    }) {
        Ok(count) => count,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn slint_native_definitions_name(list: SlintNativeDefinitionList, index: u32) -> *mut c_char {
    clear_error();
    if list.0.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        if (index as usize) >= defs.len() {
            set_error("index out of bounds".into());
            return ptr::null_mut();
        }
        match CString::new(defs[index as usize].name()) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_error("name contains null byte".into());
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_native_definitions_name".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_definitions_free(list: SlintNativeDefinitionList) {
    if !list.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(list.0 as *mut Vec<Definition>) });
        });
    }
}

// === Instance ===

#[repr(transparent)]
pub struct SlintNativeInstance(*mut c_void);

struct InstanceHandle {
    core: Instance,
    window: Rc<MinimalSoftwareWindow>,
}

#[no_mangle]
pub extern "C" fn slint_native_instantiate(
    list: SlintNativeDefinitionList,
    index: u32,
) -> SlintNativeInstance {
    clear_error();
    if list.0.is_null() {
        return SlintNativeInstance(ptr::null_mut());
    }
    match catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        if (index as usize) >= defs.len() {
            set_error("index out of bounds".into());
            return ptr::null_mut();
        }

        let instance = match defs[index as usize].instantiate() {
            Ok(i) => i,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };

        let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);

        let handle = InstanceHandle {
            core: instance,
            window,
        };

        Box::into_raw(Box::new(handle)) as *mut c_void
    }) {
        Ok(ptr) => SlintNativeInstance(ptr),
        Err(_) => {
            set_error("panicked in slint_native_instantiate".into());
            SlintNativeInstance(ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_instance_free(instance: SlintNativeInstance) {
    if !instance.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(instance.0 as *mut InstanceHandle) });
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_native_instance_set_size(instance: SlintNativeInstance, width: u32, height: u32) {
    if instance.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        handle.window.set_size(PhysicalSize::new(width, height));
    });
}

#[no_mangle]
pub extern "C" fn slint_native_instance_render(
    instance: SlintNativeInstance,
    buffer: *mut u8,
    len: usize,
) -> bool {
    clear_error();
    if instance.0.is_null() || buffer.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let size = handle.window.size();
        let expected_len = (size.width as usize) * (size.height as usize) * 4;
        if len != expected_len {
            set_error(format!(
                "buffer size mismatch: expected {}, got {}",
                expected_len, len
            ));
            return false;
        }

        let pixels = unsafe { std::slice::from_raw_parts_mut(buffer as *mut PremultipliedRgbaColor, len / 4) };

        slint::platform::update_timers_and_animations();

        let mut drawn = false;
        handle.window.draw_if_needed(|renderer| {
            renderer.render(pixels, size.width as usize);
            drawn = true;
        });

        drawn
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_native_instance_render".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_instance_pointer_event(
    instance: SlintNativeInstance,
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) {
    if instance.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Some(event) = slint_dart_core::events::pointer_event(kind, x, y, button, dx, dy) {
            let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
            let _ = handle.window.dispatch_event(event);
        }
    });
}

#[no_mangle]
pub extern "C" fn slint_native_instance_key_event(
    instance: SlintNativeInstance,
    text: *const c_char,
    pressed: bool,
) {
    if instance.0.is_null() || text.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Ok(text_str) = unsafe { CStr::from_ptr(text) }.to_str() {
            let event = slint_dart_core::events::key_event(text_str, pressed);
            let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
            let _ = handle.window.dispatch_event(event);
        }
    });
}

#[no_mangle]
pub extern "C" fn slint_native_instance_get_property(instance: SlintNativeInstance, name: *const c_char) -> *mut c_char {
    clear_error();
    if instance.0.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("property name is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        match handle.core.get_property_json(name_str) {
            Ok(json) => match CString::new(json) {
                Ok(cstr) => cstr.into_raw(),
                Err(_) => {
                    set_error("json contains null byte".into());
                    ptr::null_mut()
                }
            },
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_native_instance_get_property".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_instance_set_property(
    instance: SlintNativeInstance,
    name: *const c_char,
    json: *const c_char,
) -> bool {
    clear_error();
    if instance.0.is_null() || name.is_null() || json.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("property name is not valid UTF-8".into());
                return false;
            }
        };
        let json_str = match unsafe { CStr::from_ptr(json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("json is not valid UTF-8".into());
                return false;
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        match handle.core.set_property_json(name_str, json_str) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_native_instance_set_property".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_native_instance_invoke(
    instance: SlintNativeInstance,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    clear_error();
    if instance.0.is_null() || name.is_null() || args_json.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("callback name is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };
        let args_str = match unsafe { CStr::from_ptr(args_json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("args_json is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        match handle.core.invoke_json(name_str, args_str) {
            Ok(result) => match CString::new(result) {
                Ok(cstr) => cstr.into_raw(),
                Err(_) => {
                    set_error("result contains null byte".into());
                    ptr::null_mut()
                }
            },
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_native_instance_invoke".into());
            ptr::null_mut()
        }
    }
}

// === String memory management ===

#[no_mangle]
pub extern "C" fn slint_native_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { CString::from_raw(s) });
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_native_last_error() -> *mut c_char {
    match get_error() {
        Some(err) => match CString::new(err) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}
