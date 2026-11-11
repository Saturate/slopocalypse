//! Thin gdext binding: exposes missions_core to GDScript and nothing else.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;

struct MissionsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MissionsExtension {}

/// GDScript: `BuildingSupport.unsupported(roof, edges, anchors, broken, max_span)`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct BuildingSupport {
    base: Base<RefCounted>,
}

#[godot_api]
impl BuildingSupport {
    /// Segments still standing that nothing holds up any more. `roof[i]` is 1 for roof
    /// segments; `edges` holds pairs of connected segment ids; `anchors` and `broken` are ids.
    #[func]
    fn unsupported(
        roof: PackedByteArray,
        edges: PackedInt32Array,
        anchors: PackedInt32Array,
        broken: PackedInt32Array,
        max_span: i64,
    ) -> PackedInt32Array {
        let roof: Vec<bool> = roof.as_slice().iter().map(|&r| r != 0).collect();
        let ids = |a: &PackedInt32Array| -> Vec<usize> {
            a.as_slice()
                .iter()
                .filter(|&&i| i >= 0 && (i as usize) < roof.len())
                .map(|&i| i as usize)
                .collect()
        };
        let n = roof.len() as i32;
        let edges: Vec<(usize, usize)> = edges
            .as_slice()
            .chunks_exact(2)
            .filter(|p| p.iter().all(|&i| (0..n).contains(&i)))
            .map(|p| (p[0] as usize, p[1] as usize))
            .collect();
        missions_core::unsupported(
            &roof,
            &edges,
            &ids(&anchors),
            &ids(&broken),
            max_span.max(0) as usize,
        )
        .into_iter()
        .map(|i| i as i32)
        .collect()
    }
}
