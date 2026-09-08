use slint_dart_interpreter::{Definition, Engine as DartEngine, Instance};
use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic;
use std::ptr;

// Thread-local error storage
thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = RefCell::new(None);
}

/// Set last error and return null
fn set_error(msg: impl Into<String>) -> *mut c_void {
    let msg = msg.into();
    let _ = LAST_ERROR.try_with(|e| {
        *e.borrow_mut() = CString::new(msg).ok();
    });
    ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn slint_skia_last_error() -> *mut c_char {
    LAST_ERROR.with(|e| match e.borrow_mut().take() {
        Some(s) => s.into_raw(),
        None => ptr::null_mut(),
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Opaque handles for C API consumers
pub struct OpaqueEngine(DartEngine);
pub struct OpaqueDefinition(Definition);
pub struct OpaqueInstance(Instance);

type c_void = std::os::raw::c_void;

#[no_mangle]
pub extern "C" fn slint_skia_engine_new() -> *mut c_void {
    panic::catch_unwind(|| {
        let engine = DartEngine::new();
        Box::into_raw(Box::new(OpaqueEngine(engine))) as *mut c_void
    })
    .unwrap_or_else(|_| set_error("Engine creation panic"))
}

#[no_mangle]
pub extern "C" fn slint_skia_engine_free(engine: *mut c_void) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine as *mut OpaqueEngine);
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_skia_engine_compile(
    engine: *mut c_void,
    source: *const c_char,
    path: *const c_char,
) -> *mut c_void {
    panic::catch_unwind(|| {
        if engine.is_null() || source.is_null() || path.is_null() {
            return set_error("null pointer");
        }

        let source_str = match unsafe { CStr::from_ptr(source) }.to_str() {
            Ok(s) => s,
            Err(e) => return set_error(e.to_string()),
        };
        let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
            Ok(s) => s,
            Err(e) => return set_error(e.to_string()),
        };

        let engine = unsafe { &mut *(engine as *mut OpaqueEngine) };
        let engine_inner = &mut engine.0;

        match engine_inner.compile(source_str, path_str) {
            // The compiler hands definitions back in HashMap order, so "the
            // first" would be a coin flip: this backend takes exactly one.
            Ok(mut defs) => match defs.len() {
                1 => Box::into_raw(Box::new(OpaqueDefinition(defs.remove(0)))) as *mut c_void,
                0 => set_error("no definitions compiled"),
                n => {
                    let names: Vec<String> = defs.iter().map(|d| d.name()).collect();
                    set_error(format!(
                        "slint_skia takes a file exporting exactly one component, got {n}: {}",
                        names.join(", ")
                    ))
                }
            },
            Err(e) => set_error(e),
        }
    })
    .unwrap_or_else(|_| set_error("Compile panic"))
}

/// `slint_skia_engine_compile` returns the one definition itself, so the
/// "list" it enumerates is that definition: count 1, name at index 0.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_count(definition: *mut c_void) -> usize {
    usize::from(!definition.is_null())
}

/// Caller frees with [slint_skia_string_free]; null for a bad index.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_name(
    definition: *mut c_void,
    index: usize,
) -> *mut c_char {
    if definition.is_null() || index != 0 {
        return ptr::null_mut();
    }
    panic::catch_unwind(|| {
        let def = unsafe { &*(definition as *mut OpaqueDefinition) };
        CString::new(def.0.name()).map_or(ptr::null_mut(), CString::into_raw)
    })
    .unwrap_or_else(|_| {
        set_error("Definition name panic");
        ptr::null_mut()
    })
}

/// Frees what [slint_skia_engine_compile] returned.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_free(definition: *mut c_void) {
    if !definition.is_null() {
        unsafe {
            let _ = Box::from_raw(definition as *mut OpaqueDefinition);
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_skia_instantiate(definition: *mut c_void) -> *mut c_void {
    panic::catch_unwind(|| {
        if definition.is_null() {
            return set_error("null definition");
        }

        let def = unsafe { &*(definition as *mut OpaqueDefinition) };
        match def.0.instantiate() {
            Ok(inst) => Box::into_raw(Box::new(OpaqueInstance(inst))) as *mut c_void,
            Err(e) => set_error(e),
        }
    })
    .unwrap_or_else(|_| set_error("Instantiate panic"))
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_free(instance: *mut c_void) {
    if !instance.is_null() {
        unsafe {
            let _ = Box::from_raw(instance as *mut OpaqueInstance);
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_set_size(
    instance: *mut c_void,
    width: f32,
    height: f32,
) -> bool {
    panic::catch_unwind(|| {
        if instance.is_null() {
            set_error("null instance");
            return false;
        }

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        // ponytail: size plumbing when window adapter is implemented
        // For now, silently succeed
        true
    })
    .unwrap_or_else(|_| {
        set_error("Set size panic");
        false
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_render(instance: *mut c_void) -> bool {
    panic::catch_unwind(|| {
        if instance.is_null() {
            set_error("null instance");
            return false;
        }
        // ponytail: GPU surface plumbing is per-platform work; slint_interpreter software path is the working reference
        // See README for architecture plan: WindowAdapter owning i_slint_renderer_skia::SkiaRenderer
        // bound to platform surface (Metal on macOS/iOS, GL/Vulkan on Android/Linux/Windows),
        // frame exported to Flutter as external texture.
        false
    })
    .unwrap_or_else(|_| {
        set_error("Render panic");
        false
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_texture_id(instance: *mut c_void) -> i64 {
    panic::catch_unwind(|| {
        if instance.is_null() {
            set_error("null instance");
            return -1;
        }
        // ponytail: external texture plumbing when renderer is integrated
        -1
    })
    .unwrap_or_else(|_| {
        set_error("Texture ID panic");
        -1
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_pointer_event(
    instance: *mut c_void,
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) -> bool {
    panic::catch_unwind(|| {
        if instance.is_null() {
            set_error("null instance");
            return false;
        }

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        // ponytail: event routing when window adapter exists
        true
    })
    .unwrap_or_else(|_| {
        set_error("Pointer event panic");
        false
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_key_event(
    instance: *mut c_void,
    text: *const c_char,
    pressed: bool,
) -> bool {
    panic::catch_unwind(|| {
        if instance.is_null() || text.is_null() {
            set_error("null pointer");
            return false;
        }

        let _text_str = unsafe { CStr::from_ptr(text) }
            .to_str()
            .map_err(|e| e.to_string());

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        // ponytail: event routing when window adapter exists
        true
    })
    .unwrap_or_else(|_| {
        set_error("Key event panic");
        false
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_get_property(
    instance: *mut c_void,
    name: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        if instance.is_null() || name.is_null() {
            set_error("null pointer");
            return ptr::null_mut();
        }

        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(e) => return set_error(e.to_string()) as *mut c_char,
        };

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        match inst.0.get_property_json(name_str) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(e) => set_error(e.to_string()) as *mut c_char,
            },
            Err(e) => set_error(e) as *mut c_char,
        }
    })
    .unwrap_or_else(|_| set_error("Get property panic") as *mut c_char)
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_set_property(
    instance: *mut c_void,
    name: *const c_char,
    value_json: *const c_char,
) -> bool {
    panic::catch_unwind(|| {
        if instance.is_null() || name.is_null() || value_json.is_null() {
            set_error("null pointer");
            return false;
        }

        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(e) => {
                set_error(e.to_string());
                return false;
            }
        };

        let value_str = match unsafe { CStr::from_ptr(value_json) }.to_str() {
            Ok(s) => s,
            Err(e) => {
                set_error(e.to_string());
                return false;
            }
        };

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        match inst.0.set_property_json(name_str, value_str) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    })
    .unwrap_or_else(|_| {
        set_error("Set property panic");
        false
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_invoke(
    instance: *mut c_void,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        if instance.is_null() || name.is_null() || args_json.is_null() {
            set_error("null pointer");
            return ptr::null_mut();
        }

        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(e) => return set_error(e.to_string()) as *mut c_char,
        };

        let args_str = match unsafe { CStr::from_ptr(args_json) }.to_str() {
            Ok(s) => s,
            Err(e) => return set_error(e.to_string()) as *mut c_char,
        };

        let inst = unsafe { &*(instance as *mut OpaqueInstance) };
        match inst.0.invoke_json(name_str, args_str) {
            Ok(result) => match CString::new(result) {
                Ok(cs) => cs.into_raw(),
                Err(e) => set_error(e.to_string()) as *mut c_char,
            },
            Err(e) => set_error(e) as *mut c_char,
        }
    })
    .unwrap_or_else(|_| set_error("Invoke panic") as *mut c_char)
}
