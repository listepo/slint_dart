#![allow(non_camel_case_types)]

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::ptr;
use std::rc::Rc;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType, PremultipliedRgbaColor};
use slint::ComponentHandle;
use slint::PhysicalSize;
use slint::Model;
use slint::VecModel;
use slint::ModelRc;

slint::include_modules!();

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
    static NEXT_WINDOW: RefCell<Option<Rc<MinimalSoftwareWindow>>> = RefCell::new(None);
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

struct FlutterSoftwarePlatform;

impl slint::platform::Platform for FlutterSoftwarePlatform {
    fn create_window_adapter(
        &self,
    ) -> Result<Rc<dyn slint::platform::WindowAdapter>, slint::PlatformError> {
        let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
        NEXT_WINDOW.with(|slot| *slot.borrow_mut() = Some(window.clone()));
        Ok(window)
    }
}

fn ensure_platform_initialized() {
    let _ = slint::platform::set_platform(Box::new(FlutterSoftwarePlatform));
}

struct TodoAppHandle {
    app: TodoApp,
    window: Rc<MinimalSoftwareWindow>,
}

#[repr(transparent)]
pub struct slint_compiler_todo_handle(*mut c_void);

// === Error Management ===

#[no_mangle]
pub extern "C" fn slint_compiler_last_error() -> *mut c_char {
    match get_error() {
        Some(err) => match CString::new(err) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { CString::from_raw(s) });
        });
    }
}

// === TodoApp Lifecycle ===

#[no_mangle]
pub extern "C" fn slint_compiler_todo_new() -> slint_compiler_todo_handle {
    clear_error();
    ensure_platform_initialized();
    match catch_unwind(|| {
        let app = match TodoApp::new() {
            Ok(a) => a,
            Err(e) => {
                set_error(format!("TodoApp::new failed: {:?}", e));
                return ptr::null_mut();
            }
        };

        if let Err(e) = app.show() {
            set_error(format!("show() failed: {:?}", e));
            return ptr::null_mut();
        }

        let window = match NEXT_WINDOW.with(|slot| slot.borrow_mut().take()) {
            Some(w) => w,
            None => {
                set_error("platform did not create a window".into());
                return ptr::null_mut();
            }
        };

        let handle = TodoAppHandle { app, window };
        Box::into_raw(Box::new(handle)) as *mut c_void
    }) {
        Ok(ptr) => slint_compiler_todo_handle(ptr),
        Err(_) => {
            set_error("panicked in slint_compiler_todo_new".into());
            slint_compiler_todo_handle(ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_free(handle: slint_compiler_todo_handle) {
    if !handle.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(handle.0 as *mut TodoAppHandle) });
        });
    }
}

// === Window Management ===

#[no_mangle]
pub extern "C" fn slint_compiler_todo_set_size(handle: slint_compiler_todo_handle, width: u32, height: u32) {
    if handle.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.window.set_size(PhysicalSize::new(width, height));
    });
}

// === Rendering ===

#[no_mangle]
pub extern "C" fn slint_compiler_todo_render(
    handle: slint_compiler_todo_handle,
    buffer: *mut u8,
    len: usize,
) -> bool {
    clear_error();
    if handle.0.is_null() || buffer.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        let size = h.window.size();
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
        h.window.draw_if_needed(|renderer| {
            renderer.render(pixels, size.width as usize);
            drawn = true;
        });

        drawn
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_render".into());
            false
        }
    }
}

// === Input Events ===

#[no_mangle]
pub extern "C" fn slint_compiler_todo_pointer_event(
    handle: slint_compiler_todo_handle,
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) {
    if handle.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Some(event) = slint_dart_core::events::pointer_event(kind, x, y, button, dx, dy) {
            let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
            let _ = h.window.dispatch_event(event);
        }
    });
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_key_event(
    handle: slint_compiler_todo_handle,
    text: *const c_char,
    pressed: bool,
) {
    if handle.0.is_null() || text.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Ok(text_str) = unsafe { CStr::from_ptr(text) }.to_str() {
            let event = slint_dart_core::events::key_event(text_str, pressed);
            let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
            let _ = h.window.dispatch_event(event);
        }
    });
}

// === Model Access ===

#[no_mangle]
pub extern "C" fn slint_compiler_todo_get_model(handle: slint_compiler_todo_handle) -> *mut c_char {
    clear_error();
    if handle.0.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        let model = h.app.get_todo_model();

        let mut items = Vec::new();
        for i in 0..model.row_count() {
            if let Some(item) = model.row_data(i) {
                let obj = serde_json::json!({
                    "title": item.title.to_string(),
                    "checked": item.checked,
                });
                items.push(obj);
            }
        }

        let json_str = serde_json::to_string(&items).unwrap_or_default();
        match CString::new(json_str) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_error("JSON contains null byte".into());
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_get_model".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_set_model(
    handle: slint_compiler_todo_handle,
    json: *const c_char,
) -> bool {
    clear_error();
    if handle.0.is_null() || json.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let json_str = match unsafe { CStr::from_ptr(json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("json is not valid UTF-8".into());
                return false;
            }
        };

        let parsed: Vec<serde_json::Value> = match serde_json::from_str(json_str) {
            Ok(v) => v,
            Err(e) => {
                set_error(format!("Failed to parse JSON: {}", e));
                return false;
            }
        };

        let mut items = Vec::new();
        for obj in parsed {
            let title = obj["title"]
                .as_str()
                .unwrap_or("")
                .to_string()
                .into();
            let checked = obj["checked"].as_bool().unwrap_or(false);
            items.push(TodoItem { title, checked });
        }

        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.set_todo_model(ModelRc::new(VecModel::from(items)));
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_set_model".into());
            false
        }
    }
}

// === Callback Registration ===

pub type slint_compiler_callback_add_todo = extern "C" fn(user_data: *mut c_void, text: *const c_char);
pub type slint_compiler_callback_toggle_todo = extern "C" fn(user_data: *mut c_void, index: i32, checked: bool);
pub type slint_compiler_callback_remove_done = extern "C" fn(user_data: *mut c_void);

#[no_mangle]
pub extern "C" fn slint_compiler_todo_on_add_todo(
    handle: slint_compiler_todo_handle,
    cb: slint_compiler_callback_add_todo,
    user_data: *mut c_void,
) -> bool {
    if handle.0.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.on_add_todo(move |text| {
            if let Ok(cstr) = CString::new(text.to_string()) {
                cb(user_data, cstr.as_ptr());
            }
        });
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_on_add_todo".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_on_toggle_todo(
    handle: slint_compiler_todo_handle,
    cb: slint_compiler_callback_toggle_todo,
    user_data: *mut c_void,
) -> bool {
    if handle.0.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.on_toggle_todo(move |index, checked| {
            cb(user_data, index, checked);
        });
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_on_toggle_todo".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_on_remove_done(
    handle: slint_compiler_todo_handle,
    cb: slint_compiler_callback_remove_done,
    user_data: *mut c_void,
) -> bool {
    if handle.0.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.on_remove_done(move || {
            cb(user_data);
        });
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_on_remove_done".into());
            false
        }
    }
}

// === Callback Invocation ===
// Mirrors the interpreter path's invoke; drives the registered handlers.

#[no_mangle]
pub extern "C" fn slint_compiler_todo_invoke_add_todo(
    handle: slint_compiler_todo_handle,
    text: *const c_char,
) -> bool {
    clear_error();
    if handle.0.is_null() || text.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let text_str = match unsafe { CStr::from_ptr(text) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("text is not valid UTF-8".into());
                return false;
            }
        };
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.invoke_add_todo(text_str.into());
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_invoke_add_todo".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_invoke_toggle_todo(
    handle: slint_compiler_todo_handle,
    index: i32,
    checked: bool,
) -> bool {
    clear_error();
    if handle.0.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.invoke_toggle_todo(index, checked);
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_invoke_toggle_todo".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_compiler_todo_invoke_remove_done(handle: slint_compiler_todo_handle) -> bool {
    clear_error();
    if handle.0.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let h = unsafe { &*(handle.0 as *const TodoAppHandle) };
        h.app.invoke_remove_done();
        true
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_compiler_todo_invoke_remove_done".into());
            false
        }
    }
}
