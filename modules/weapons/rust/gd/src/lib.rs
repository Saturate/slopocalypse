//! gdext binding for weapons_core: GDScript gets `WeaponRules`.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;
use weapons_core::{WeaponState, WeaponStats};

struct WeaponsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for WeaponsExtension {}

/// GDScript: `var rules := WeaponRules.new(); rules.setup(600.0, 30, 2.0, 0.01, seed)`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct WeaponRules {
    state: Option<WeaponState>,
    base: Base<RefCounted>,
}

#[godot_api]
impl WeaponRules {
    #[func]
    fn setup(
        &mut self,
        rounds_per_minute: f64,
        magazine: i64,
        reload_seconds: f64,
        spread_radians: f64,
        seed: i64,
    ) {
        let stats = WeaponStats {
            rounds_per_minute,
            magazine: u32::try_from(magazine).unwrap_or(0),
            reload_seconds,
            spread_radians,
        };
        // The seed's bits matter, not its sign.
        self.state = Some(WeaponState::new(stats, seed as u64));
    }

    #[func]
    fn tick(&mut self, delta: f64) {
        if let Some(s) = self.state.as_mut() {
            s.tick(delta);
        }
    }

    /// True when a shot happened; read its spread with `last_spread()`.
    #[func]
    fn try_fire(&mut self) -> bool {
        self.state.as_mut().is_some_and(|s| s.try_fire().is_ok())
    }

    /// (yaw, pitch) offset of the last shot in radians.
    #[func]
    fn last_spread(&self) -> Vector2 {
        let (yaw, pitch) = self.state.as_ref().map_or((0.0, 0.0), |s| s.last_spread());
        Vector2::new(yaw as f32, pitch as f32)
    }

    #[func]
    fn start_reload(&mut self) -> bool {
        self.state.as_mut().is_some_and(|s| s.start_reload())
    }

    #[func]
    fn ammo(&self) -> i64 {
        self.state.as_ref().map_or(0, |s| i64::from(s.ammo()))
    }

    #[func]
    fn is_reloading(&self) -> bool {
        self.state.as_ref().is_some_and(|s| s.is_reloading())
    }
}
