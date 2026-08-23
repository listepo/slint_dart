use serde_json::Value as JsonValue;
use slint_interpreter::{ComponentDefinition, ComponentInstance, Value, Compiler};

/// Wraps slint_interpreter::Compiler for building and managing Slint components.
pub struct Engine {
    compiler: Compiler,
}

impl Engine {
    /// Create a new Engine instance.
    pub fn new() -> Self {
        Engine {
            compiler: Compiler::default(),
        }
    }

    /// Compile Slint source code and return a list of component definitions.
    /// On error, returns diagnostics joined with newlines.
    pub fn compile(&mut self, source: &str, path: &str) -> Result<Vec<Definition>, String> {
        let source_str = source.to_string();
        let path_buf = std::path::PathBuf::from(path);

        let result = spin_on::spin_on(self.compiler.build_from_source(source_str, path_buf));

        // Collect diagnostics and check if there are errors.
        let diag_vec: Vec<_> = result.diagnostics().collect();
        if !diag_vec.is_empty() {
            let diags = diag_vec
                .iter()
                .map(|d| d.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            return Err(diags);
        }

        // Convert ComponentDefinition to Definition wrapper.
        let defs = result
            .components()
            .map(Definition)
            .collect();

        Ok(defs)
    }
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

/// Wraps slint_interpreter::ComponentDefinition.
pub struct Definition(pub ComponentDefinition);

impl Definition {
    /// Get the component name.
    pub fn name(&self) -> String {
        self.0.name().to_string()
    }

    /// Instantiate this component definition into a running instance.
    pub fn instantiate(&self) -> Result<Instance, String> {
        self.0
            .create()
            .map(Instance)
            .map_err(|e| format!("{:?}", e))
    }
}

/// Wraps slint_interpreter::ComponentInstance.
pub struct Instance(pub ComponentInstance);

impl Instance {
    /// Get a property value as JSON string.
    pub fn get_property_json(&self, name: &str) -> Result<String, String> {
        let value = self.0.get_property(name)
            .map_err(|e| format!("Failed to get property '{}': {:?}", name, e))?;
        value_to_json(&value)
    }

    /// Set a property value from a JSON string.
    pub fn set_property_json(&self, name: &str, json: &str) -> Result<(), String> {
        let value = value_from_json(json)?;
        self.0.set_property(name, value)
            .map_err(|e| format!("Failed to set property '{}': {:?}", name, e))
    }

    /// Invoke a callback or method with JSON array arguments, returning JSON result.
    pub fn invoke_json(&self, name: &str, args_json: &str) -> Result<String, String> {
        let args_val: JsonValue = serde_json::from_str(args_json)
            .map_err(|e| format!("Failed to parse args JSON: {}", e))?;

        let args_array = args_val.as_array()
            .ok_or_else(|| "args_json must be a JSON array".to_string())?;

        let args: Vec<Value> = args_array
            .iter()
            .map(|v| json_to_value_internal(v))
            .collect::<Result<Vec<_>, String>>()?;

        let result = self.0.invoke(name, &args)
            .map_err(|e| format!("Failed to invoke '{}': {:?}", name, e))?;

        value_to_json(&result)
    }
}

/// Convert a slint Value to a JSON string.
/// Supports: Bool, Number, String, Void.
pub fn value_to_json(v: &Value) -> Result<String, String> {
    let json = match v {
        Value::Bool(b) => JsonValue::Bool(*b),
        Value::Number(n) => {
            if n.fract() == 0.0 && *n >= i64::MIN as f64 && *n <= i64::MAX as f64 {
                JsonValue::Number((*n as i64).to_string().parse().unwrap())
            } else {
                JsonValue::Number(n.to_string().parse().unwrap())
            }
        }
        Value::String(s) => JsonValue::String(s.to_string()),
        Value::Void => JsonValue::Null,
        _ => return Err(format!("Unsupported value type in JSON conversion: {:?}", v)),
    };

    serde_json::to_string(&json)
        .map_err(|e| format!("Failed to serialize JSON: {}", e))
}

/// Convert JSON to a slint Value.
/// Supports: Bool, Number, String, Null (Void).
pub fn value_from_json(json: &str) -> Result<Value, String> {
    let v: JsonValue = serde_json::from_str(json)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    json_to_value_internal(&v)
}

fn json_to_value_internal(v: &JsonValue) -> Result<Value, String> {
    match v {
        JsonValue::Bool(b) => Ok(Value::Bool(*b)),
        JsonValue::Number(n) => {
            let num = n.as_f64()
                .ok_or_else(|| "Invalid number in JSON".to_string())?;
            Ok(Value::Number(num))
        }
        JsonValue::String(s) => Ok(Value::String(s.into())),
        JsonValue::Null => Ok(Value::Void),
        JsonValue::Array(_) => Err("Arrays are not supported in JSON value conversion".to_string()),
        JsonValue::Object(_) => Err("Objects are not supported in JSON value conversion".to_string()),
    }
}

/// Event handling utilities for pointer and keyboard input.
pub mod events {
    use slint::platform::WindowEvent;
    use slint::platform::PointerEventButton;
    use slint::LogicalPosition;

    /// Create a pointer event from raw parameters.
    /// kind: 0=move, 1=down, 2=up, 3=scroll, 4=exit
    /// button: 0=none, 1=left, 2=right, 3=middle
    /// dx/dy: delta for scroll, movement for move
    pub fn pointer_event(
        kind: u8,
        x: f32,
        y: f32,
        button: u8,
        dx: f32,
        dy: f32,
    ) -> Option<WindowEvent> {
        let position = LogicalPosition::new(x, y);

        match kind {
            0 => Some(WindowEvent::PointerMoved { position }),
            1 => {
                let btn = match button {
                    1 => PointerEventButton::Left,
                    2 => PointerEventButton::Right,
                    3 => PointerEventButton::Middle,
                    _ => return None,
                };
                Some(WindowEvent::PointerPressed { position, button: btn })
            }
            2 => {
                let btn = match button {
                    1 => PointerEventButton::Left,
                    2 => PointerEventButton::Right,
                    3 => PointerEventButton::Middle,
                    _ => return None,
                };
                Some(WindowEvent::PointerReleased { position, button: btn })
            }
            3 => Some(WindowEvent::PointerScrolled {
                position,
                delta_x: dx,
                delta_y: dy,
            }),
            4 => Some(WindowEvent::PointerExited),
            _ => None,
        }
    }

    /// Create a keyboard event.
    pub fn key_event(text: &str, pressed: bool) -> WindowEvent {
        if pressed {
            WindowEvent::KeyPressed {
                text: text.into(),
            }
        } else {
            WindowEvent::KeyReleased {
                text: text.into(),
            }
        }
    }
}
