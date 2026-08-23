//! Dumps the public interface of a `.slint` file as JSON on stdout.
//!
//! Used by `slint_compiler` (Dart) as the single schema source for both the
//! generated `.g.dart` wrappers and the generated AOT Rust glue crate. Unlike
//! `slint-interpreter` introspection, this exposes full types: struct fields,
//! array element types, and callback signatures.

use std::process::exit;
use std::rc::Rc;

use i_slint_compiler::diagnostics::BuildDiagnostics;
use i_slint_compiler::langtype::Type;
use i_slint_compiler::object_tree::{Component, PropertyVisibility};
use serde_json::{json, Value};

fn main() {
    let path = match std::env::args().nth(1) {
        Some(p) => p,
        None => {
            eprintln!("usage: slint-introspect <file.slint>");
            exit(64);
        }
    };

    let mut diag = BuildDiagnostics::default();
    let syntax_node = i_slint_compiler::parser::parse_file(&path, &mut diag);
    if diag.has_errors() {
        for d in diag.to_string_vec() {
            eprintln!("{d}");
        }
        exit(1);
    }
    let config = i_slint_compiler::CompilerConfiguration::new(
        i_slint_compiler::generator::OutputFormat::Rust,
    );
    let (doc, diag, _loader) = spin_on::spin_on(i_slint_compiler::compile_syntax_node(
        syntax_node.expect("no parse errors"),
        diag,
        config,
    ));
    if diag.has_errors() {
        for d in diag.to_string_vec() {
            eprintln!("{d}");
        }
        exit(1);
    }

    let mut components = Vec::new();
    for (name, export) in doc.exports.iter() {
        let Some(c) = export.as_ref().left() else {
            continue;
        };
        if c.is_global() {
            continue;
        }
        match component_json(&name.name, c) {
            Ok(v) => components.push(v),
            Err(e) => {
                eprintln!("{}: {e}", name.name);
                exit(1);
            }
        }
    }
    println!("{}", json!({ "components": components }));
}

fn component_json(export_name: &str, c: &Rc<Component>) -> Result<Value, String> {
    let root = c.root_element.borrow();
    let mut properties = Vec::new();
    let mut callbacks = Vec::new();
    for (name, decl) in root.property_declarations.iter() {
        // Compiler passes hoist internal widget properties into the root;
        // only user-declared API carries expose_in_public_api.
        if !decl.expose_in_public_api {
            continue;
        }
        match &decl.property_type {
            Type::Callback(f) => {
                let args = f
                    .args
                    .iter()
                    .map(type_json)
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|e| format!("callback '{name}': {e}"))?;
                let ret = match &f.return_type {
                    Type::Void => Value::Null,
                    t => type_json(t).map_err(|e| format!("callback '{name}': {e}"))?,
                };
                callbacks.push(json!({ "name": name.to_string(), "args": args, "return": ret }));
            }
            // ponytail: public functions not bridged; add when needed
            Type::Function(_) => {}
            ty => {
                if matches!(
                    decl.visibility,
                    PropertyVisibility::Input
                        | PropertyVisibility::Output
                        | PropertyVisibility::InOut
                ) {
                    let t = type_json(ty).map_err(|e| format!("property '{name}': {e}"))?;
                    properties.push(json!({ "name": name.to_string(), "type": t }));
                }
            }
        }
    }
    Ok(json!({ "name": export_name, "properties": properties, "callbacks": callbacks }))
}

fn type_json(t: &Type) -> Result<Value, String> {
    Ok(match t {
        Type::Float32 => json!({"kind": "float"}),
        Type::Int32 => json!({"kind": "int"}),
        Type::String => json!({"kind": "string"}),
        Type::Bool => json!({"kind": "bool"}),
        Type::Duration => json!({"kind": "duration"}),
        Type::Angle => json!({"kind": "angle"}),
        Type::Percent => json!({"kind": "percent"}),
        Type::PhysicalLength | Type::LogicalLength | Type::Rem => json!({"kind": "length"}),
        Type::Array(inner) => json!({"kind": "array", "element": type_json(inner)?}),
        Type::Struct(s) => {
            let name = s.name.slint_name().ok_or_else(|| {
                "anonymous structs are not supported; declare a named struct".to_string()
            })?;
            let fields = s
                .fields
                .iter()
                .map(|(k, v)| Ok(json!({"name": k.to_string(), "type": type_json(v)?})))
                .collect::<Result<Vec<_>, String>>()?;
            json!({"kind": "struct", "name": name.to_string(), "fields": fields})
        }
        other => {
            return Err(format!(
                "unsupported type `{other}` (supported: numbers, string, bool, named structs, arrays)"
            ))
        }
    })
}
