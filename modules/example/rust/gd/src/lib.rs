//! Thin gdext binding: exposes example_core to GDScript and nothing else.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;

struct ExampleExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ExampleExtension {}

/// GDScript: `ExampleRules.new().double(21)`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct ExampleRules {
    base: Base<RefCounted>,
}

#[godot_api]
impl ExampleRules {
    #[func]
    fn double(&self, value: i64) -> i64 {
        example_core::double(value)
    }
}
