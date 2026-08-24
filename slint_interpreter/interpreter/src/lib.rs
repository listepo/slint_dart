//! Runtime `.slint` path: wraps `slint-interpreter` behind a renderer-agnostic
//! engine API (compile, instantiate, JSON value bridge, callbacks).
//!
//! This crate never depends on build-time codegen (`slint-build`); the
//! compile-time path is the `slint_compiler`-generated AOT crate.
//! Renderer-agnostic event mapping lives in `slint-dart-core`.

use serde_json::Value as JsonValue;
use slint::Model;
use slint_interpreter::{Compiler, ComponentDefinition, ComponentInstance, Value};

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
    /// Fails only when no component was produced; warning-level diagnostics
    /// do not abort the build.
    pub fn compile(&mut self, source: &str, path: &str) -> Result<Vec<Definition>, String> {
        let source_str = source.to_string();
        let path_buf = std::path::PathBuf::from(path);

        let result = spin_on::spin_on(self.compiler.build_from_source(source_str, path_buf));

        let defs: Vec<Definition> = result.components().map(Definition).collect();
        if defs.is_empty() {
            let diags = result
                .diagnostics()
                .map(|d| d.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            return Err(if diags.is_empty() {
                "no exported component found".to_string()
            } else {
                diags
            });
        }

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
        let value = self
            .0
            .get_property(name)
            .map_err(|e| format!("Failed to get property '{}': {:?}", name, e))?;
        value_to_json(&value)
    }

    /// Set a property value from a JSON string.
    pub fn set_property_json(&self, name: &str, json: &str) -> Result<(), String> {
        let value = value_from_json(json)?;
        self.0
            .set_property(name, value)
            .map_err(|e| format!("Failed to set property '{}': {:?}", name, e))
    }

    /// Invoke a callback or method with JSON array arguments, returning JSON result.
    pub fn invoke_json(&self, name: &str, args_json: &str) -> Result<String, String> {
        let args_val: JsonValue = serde_json::from_str(args_json)
            .map_err(|e| format!("Failed to parse args JSON: {}", e))?;

        let args_array = args_val
            .as_array()
            .ok_or_else(|| "args_json must be a JSON array".to_string())?;

        let args: Vec<Value> = args_array
            .iter()
            .map(json_to_value_internal)
            .collect::<Result<Vec<_>, String>>()?;

        let result = self
            .0
            .invoke(name, &args)
            .map_err(|e| format!("Failed to invoke '{}': {:?}", name, e))?;

        value_to_json(&result)
    }

    /// Register a host callback; arguments arrive as a JSON array string.
    /// Callback return values are ignored (Slint side gets Void).
    pub fn set_callback_json(
        &self,
        name: &str,
        f: Box<dyn Fn(&str) + 'static>,
    ) -> Result<(), String> {
        self.0
            .set_callback(name, move |args: &[Value]| {
                let json_arr: Result<Vec<JsonValue>, String> =
                    args.iter().map(value_to_json_internal).collect();
                match json_arr {
                    Ok(arr) => {
                        if let Ok(json_str) = serde_json::to_string(&serde_json::Value::Array(arr))
                        {
                            f(&json_str);
                        }
                    }
                    Err(_) => {
                        f("null");
                    }
                }
                Value::Void
            })
            .map_err(|e| format!("{:?}", e))
    }
}

/// Convert a slint Value to a JSON string.
// ponytail: images/brushes not bridged; add when needed
pub fn value_to_json(v: &Value) -> Result<String, String> {
    let json = value_to_json_internal(v)?;
    serde_json::to_string(&json).map_err(|e| format!("Failed to serialize JSON: {}", e))
}

fn value_to_json_internal(v: &Value) -> Result<JsonValue, String> {
    match v {
        Value::Void => Ok(JsonValue::Null),
        Value::Bool(b) => Ok(JsonValue::Bool(*b)),
        Value::Number(n) => {
            if n.fract() == 0.0 && *n >= i64::MIN as f64 && *n <= i64::MAX as f64 {
                Ok(JsonValue::Number((*n as i64).into()))
            } else {
                Ok(JsonValue::Number(
                    serde_json::Number::from_f64(*n).unwrap_or_else(|| serde_json::Number::from(0)),
                ))
            }
        }
        Value::String(s) => Ok(JsonValue::String(s.to_string())),
        Value::Model(m) => {
            let mut arr = Vec::new();
            for i in 0..m.row_count() {
                if let Some(item) = m.row_data(i) {
                    arr.push(value_to_json_internal(&item)?);
                }
            }
            Ok(JsonValue::Array(arr))
        }
        Value::Struct(s) => {
            let mut obj = serde_json::Map::new();
            for (key, val) in s.iter() {
                obj.insert(key.to_string(), value_to_json_internal(val)?);
            }
            Ok(JsonValue::Object(obj))
        }
        _ => Err(format!(
            "Unsupported value type in JSON conversion: {:?}",
            v
        )),
    }
}

/// Convert JSON to a slint Value.
pub fn value_from_json(json: &str) -> Result<Value, String> {
    let v: JsonValue =
        serde_json::from_str(json).map_err(|e| format!("Failed to parse JSON: {}", e))?;
    json_to_value_internal(&v)
}

fn json_to_value_internal(v: &JsonValue) -> Result<Value, String> {
    match v {
        JsonValue::Null => Ok(Value::Void),
        JsonValue::Bool(b) => Ok(Value::Bool(*b)),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                Ok(Value::Number(i as f64))
            } else if let Some(u) = n.as_u64() {
                Ok(Value::Number(u as f64))
            } else {
                Ok(Value::Number(n.as_f64().unwrap_or(0.0)))
            }
        }
        JsonValue::String(s) => Ok(Value::String(s.clone().into())),
        JsonValue::Array(arr) => {
            let values: Result<Vec<Value>, String> =
                arr.iter().map(json_to_value_internal).collect();
            let values = values?;
            Ok(Value::Model(slint::ModelRc::new(slint::VecModel::from(
                values,
            ))))
        }
        JsonValue::Object(obj) => {
            let fields: Result<Vec<(String, Value)>, String> = obj
                .iter()
                .map(|(k, v)| json_to_value_internal(v).map(|val| (k.clone(), val)))
                .collect();
            let fields = fields?;
            Ok(Value::Struct(slint_interpreter::Struct::from_iter(fields)))
        }
    }
}
