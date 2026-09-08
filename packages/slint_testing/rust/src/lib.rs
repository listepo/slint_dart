#![allow(non_camel_case_types)]
// C ABI entry points: only ever called through the C ABI with the pointer
// contract in the header — marking them `unsafe fn` changes nothing for
// those callers, and every dereference is already an explicit unsafe block.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

//! C ABI over `i-slint-backend-testing`: instantiate a `.slint` component on
//! the testing platform and inspect it through the accessibility tree, so
//! tests assert on elements rather than pixels.
//!
//! Everything here is synchronous. The testing backend runs with
//! `init_no_event_loop`, so clicks go through the accessible *default action*
//! rather than the async pointer-event helpers, which need a running event
//! loop.

use std::cell::{Cell, RefCell};
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::ptr;
use std::rc::Rc;
use std::time::Duration;

use i_slint_backend_testing::{init_no_event_loop, mock_elapsed_time};
use slint_dart_interpreter::{describe_all, Definition, ElementHandle, Engine, Instance};

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
    // The testing platform is per-thread (`threading: false`), and
    // `init_no_event_loop` panics if a platform is already set.
    static BACKEND_READY: Cell<bool> = const { Cell::new(false) };
}

fn set_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

fn clear_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = None);
}

fn ensure_backend() {
    BACKEND_READY.with(|ready| {
        if !ready.get() {
            init_no_event_loop();
            ready.set(true);
        }
    });
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

/// Reads a required C string argument, recording an error and returning
/// `None` when it is null or not UTF-8.
fn read_str<'a>(ptr: *const c_char, what: &str) -> Option<&'a str> {
    if ptr.is_null() {
        set_error(format!("{what} is null"));
        return None;
    }
    match unsafe { CStr::from_ptr(ptr) }.to_str() {
        Ok(s) => Some(s),
        Err(_) => {
            set_error(format!("{what} is not valid UTF-8"));
            None
        }
    }
}

/// Component names, sorted, so error messages do not vary run to run.
fn component_names(defs: &[Definition]) -> String {
    let mut names: Vec<String> = defs.iter().map(Definition::name).collect();
    names.sort();
    names.join(", ")
}

/// One component instantiated on the testing backend, plus the element
/// snapshot the last query produced and the callback calls recorded so far.
struct App {
    instance: Instance,
    elements: Vec<ElementHandle>,
    calls: Rc<RefCell<Vec<(String, String)>>>,
}

impl App {
    fn element(&self, index: usize, what: &str) -> Option<&ElementHandle> {
        match self.elements.get(index) {
            Some(e) if e.is_valid() => Some(e),
            Some(_) => {
                set_error(format!(
                    "element {index} is stale — re-run the query after {what}"
                ));
                None
            }
            None => {
                set_error(format!(
                    "element {index} out of range ({} in the last query)",
                    self.elements.len()
                ));
                None
            }
        }
    }
}

#[repr(transparent)]
pub struct SlintTestingApp(*mut c_void);

fn null_app() -> SlintTestingApp {
    SlintTestingApp(ptr::null_mut())
}

impl SlintTestingApp {
    fn get<'a>(&self) -> Option<&'a mut App> {
        if self.0.is_null() {
            set_error("null app handle".into());
            return None;
        }
        Some(unsafe { &mut *(self.0 as *mut App) })
    }
}

/// Last error, or null. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_last_error() -> *mut c_char {
    LAST_ERROR
        .with(|e| e.borrow_mut().take())
        .map_or(ptr::null_mut(), to_c_string)
}

#[no_mangle]
pub extern "C" fn slint_testing_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = catch_unwind(|| drop(unsafe { CString::from_raw(s) }));
    }
}

/// Advances the testing backend's mock clock, driving animations and timers.
#[no_mangle]
pub extern "C" fn slint_testing_elapse_ms(millis: u64) {
    clear_error();
    let _ = catch_unwind(|| {
        ensure_backend();
        mock_elapsed_time(Duration::from_millis(millis));
    });
}

/// Compiles `source` and instantiates `component` on the testing backend.
/// `component` may be null only when the source exports exactly one.
#[no_mangle]
pub extern "C" fn slint_testing_app_new(
    source: *const c_char,
    path: *const c_char,
    component: *const c_char,
) -> SlintTestingApp {
    clear_error();
    match catch_unwind(|| {
        ensure_backend();
        let Some(source) = read_str(source, "source") else {
            return null_app();
        };
        let path = if path.is_null() {
            ""
        } else {
            match read_str(path, "path") {
                Some(p) => p,
                None => return null_app(),
            }
        };
        let wanted = if component.is_null() {
            None
        } else {
            match read_str(component, "component") {
                Some(c) => Some(c),
                None => return null_app(),
            }
        };

        let mut engine = Engine::new();
        let defs = match engine.compile(source, path) {
            Ok(d) => d,
            Err(e) => {
                set_error(e);
                return null_app();
            }
        };
        let def = match wanted {
            Some(name) => match defs.iter().find(|d| d.name() == name) {
                Some(d) => d,
                None => {
                    set_error(format!(
                        "no component named '{name}' (found: {})",
                        component_names(&defs)
                    ));
                    return null_app();
                }
            },
            // The compiler hands components back in hash order, so "the first
            // one" is not the first in the source — it is arbitrary. Only omit
            // the name when there is nothing to be ambiguous about.
            None => match defs.as_slice() {
                [only] => only,
                [] => {
                    set_error("source exports no component".into());
                    return null_app();
                }
                many => {
                    set_error(format!(
                        "source exports {} components ({}) — name the one to test",
                        many.len(),
                        component_names(&defs)
                    ));
                    return null_app();
                }
            },
        };
        let instance = match def.instantiate() {
            Ok(i) => i,
            Err(e) => {
                set_error(e);
                return null_app();
            }
        };
        let app = App {
            instance,
            elements: Vec::new(),
            calls: Rc::new(RefCell::new(Vec::new())),
        };
        SlintTestingApp(Box::into_raw(Box::new(app)) as *mut c_void)
    }) {
        Ok(app) => app,
        Err(_) => {
            set_error("panicked in slint_testing_app_new".into());
            null_app()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_testing_app_free(app: SlintTestingApp) {
    if !app.0.is_null() {
        let _ = catch_unwind(|| drop(unsafe { Box::from_raw(app.0 as *mut App) }));
    }
}

/// Runs a query and returns its matches as a JSON array of element
/// descriptors, replacing the previous snapshot. `kind` is one of `label`,
/// `id`, `type`, or `all`; `needle` is ignored for `all`.
///
/// Caller frees with [slint_testing_string_free]; null means error.
#[no_mangle]
pub extern "C" fn slint_testing_app_query(
    app: SlintTestingApp,
    kind: *const c_char,
    needle: *const c_char,
) -> *mut c_char {
    clear_error();
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let Some(kind) = read_str(kind, "kind") else {
            return ptr::null_mut();
        };
        // `needle` is read only for the kinds that take one, so `all` may
        // legitimately pass null.
        let needle = if needle.is_null() {
            None
        } else {
            match read_str(needle, "needle") {
                Some(n) => Some(n),
                None => return ptr::null_mut(),
            }
        };
        let found: Vec<ElementHandle> = match app.instance.query_elements(kind, needle) {
            Ok(found) => found,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };

        let json = match describe_all(&found) {
            Ok(json) => json,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };
        app.elements = found;
        to_c_string(json)
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_query".into());
            ptr::null_mut()
        }
    }
}

/// Invokes the accessible default action of the element at `index` in the
/// last query's snapshot — a button press, a checkbox toggle.
#[no_mangle]
pub extern "C" fn slint_testing_app_click(app: SlintTestingApp, index: usize) -> bool {
    clear_error();
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(element) = app.element(index, "the click") else {
            return false;
        };
        element.invoke_accessible_default_action();
        true
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_click".into());
        false
    })
}

/// Sets the accessible value of the element at `index` — typing into a text
/// input, moving a slider.
#[no_mangle]
pub extern "C" fn slint_testing_app_set_value(
    app: SlintTestingApp,
    index: usize,
    value: *const c_char,
) -> bool {
    clear_error();
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(value) = read_str(value, "value") else {
            return false;
        };
        let Some(element) = app.element(index, "the update") else {
            return false;
        };
        element.set_accessible_value(value);
        true
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_set_value".into());
        false
    })
}

/// Property read; returns JSON. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_app_get_property(
    app: SlintTestingApp,
    name: *const c_char,
) -> *mut c_char {
    clear_error();
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let Some(name) = read_str(name, "name") else {
            return ptr::null_mut();
        };
        match app.instance.get_property_json(name) {
            Ok(json) => to_c_string(json),
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        }
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_get_property".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_testing_app_set_property(
    app: SlintTestingApp,
    name: *const c_char,
    json: *const c_char,
) -> bool {
    clear_error();
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let (Some(name), Some(json)) = (read_str(name, "name"), read_str(json, "json")) else {
            return false;
        };
        match app.instance.set_property_json(name, json) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_set_property".into());
        false
    })
}

/// Invokes a callback or function on the component; returns its result as
/// JSON. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_app_invoke(
    app: SlintTestingApp,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    clear_error();
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let (Some(name), Some(args)) = (read_str(name, "name"), read_str(args_json, "args_json"))
        else {
            return ptr::null_mut();
        };
        match app.instance.invoke_json(name, args) {
            Ok(json) => to_c_string(json),
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        }
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_invoke".into());
            ptr::null_mut()
        }
    }
}

/// Starts recording invocations of `name` into the call log. Tests assert on
/// the log instead of registering a Dart closure, which keeps the whole
/// surface synchronous and free of callback trampolines.
#[no_mangle]
pub extern "C" fn slint_testing_app_record(app: SlintTestingApp, name: *const c_char) -> bool {
    clear_error();
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(name) = read_str(name, "name") else {
            return false;
        };
        let calls = app.calls.clone();
        let recorded = name.to_string();
        match app.instance.set_callback_json(
            name,
            Box::new(move |args_json| {
                calls
                    .borrow_mut()
                    .push((recorded.clone(), args_json.to_string()));
            }),
        ) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_record".into());
        false
    })
}

/// Drains the call log as a JSON array of `{"name": …, "args": […]}`.
/// Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_app_take_calls(app: SlintTestingApp) -> *mut c_char {
    clear_error();
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let drained: Vec<(String, String)> = app.calls.borrow_mut().drain(..).collect();
        let calls: Vec<serde_json::Value> = drained
            .into_iter()
            .map(|(name, args)| {
                let args: serde_json::Value =
                    serde_json::from_str(&args).unwrap_or(serde_json::Value::Null);
                serde_json::json!({ "name": name, "args": args })
            })
            .collect();
        match serde_json::to_string(&calls) {
            Ok(json) => to_c_string(json),
            Err(e) => {
                set_error(format!("failed to serialize calls: {e}"));
                ptr::null_mut()
            }
        }
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_take_calls".into());
            ptr::null_mut()
        }
    }
}
