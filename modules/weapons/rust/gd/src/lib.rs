//! gdext binding for weapons_core: GDScript gets `WeaponRules` and `WeaponBuild`.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;
use std::collections::BTreeMap;
use weapons_core::parts::{self, BuildStats, PartDef, PartStats};
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

/// GDScript: `WeaponBuild.assemble(parts, build)` where `parts` maps part id to its data
/// (`slot`, `provides`, `stats`) and `build` maps slot to part id. Returns
/// `{ok, errors: Array[String], stats: Dictionary}`; the rules live in weapons_core::parts.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct WeaponBuild {
    base: Base<RefCounted>,
}

#[godot_api]
impl WeaponBuild {
    #[func]
    fn assemble(parts: VarDictionary, build: VarDictionary) -> VarDictionary {
        let catalogue: BTreeMap<String, PartDef> = parts
            .iter_shared()
            .filter_map(|(id, data)| {
                let id = id.try_to::<GString>().ok()?.to_string();
                let data = data.try_to::<VarDictionary>().ok()?;
                Some((id.clone(), part_from(id, &data)))
            })
            .collect();
        let slots: BTreeMap<String, String> = build
            .iter_shared()
            .filter_map(|(slot, id)| {
                Some((
                    slot.try_to::<GString>().ok()?.to_string(),
                    id.try_to::<GString>().ok()?.to_string(),
                ))
            })
            .collect();
        let mut out = VarDictionary::new();
        match parts::assemble(&catalogue, &slots) {
            Ok(stats) => {
                put(&mut out, "ok", true.to_variant());
                put(&mut out, "errors", VarArray::new().to_variant());
                put(&mut out, "stats", stats_to(&stats).to_variant());
            }
            Err(errors) => {
                let mut list = VarArray::new();
                for e in errors {
                    list.push(&e.to_string().to_variant());
                }
                put(&mut out, "ok", false.to_variant());
                put(&mut out, "errors", list.to_variant());
                put(&mut out, "stats", VarDictionary::new().to_variant());
            }
        }
        out
    }
}

fn put(d: &mut VarDictionary, key: &str, value: Variant) {
    d.set(key, &value);
}

fn num(d: &VarDictionary, key: &str) -> Option<f64> {
    d.get_or_nil(key).try_to::<f64>().ok()
}

fn part_from(id: String, data: &VarDictionary) -> PartDef {
    let slot = data
        .get_or_nil("slot")
        .try_to::<GString>()
        .map(|s| s.to_string())
        .unwrap_or_default();
    let provides = data
        .get_or_nil("provides")
        .try_to::<VarArray>()
        .map(|a| {
            a.iter_shared()
                .filter_map(|v| v.try_to::<GString>().ok())
                .map(|s| s.to_string())
                .collect()
        })
        .unwrap_or_default();
    let s = data
        .get_or_nil("stats")
        .try_to::<VarDictionary>()
        .unwrap_or_default();
    let stats = PartStats {
        rounds_per_minute: num(&s, "rounds_per_minute"),
        damage: num(&s, "damage"),
        spread_degrees: num(&s, "spread_degrees"),
        recoil_pitch_degrees: num(&s, "recoil_pitch_degrees"),
        recoil_yaw_degrees: num(&s, "recoil_yaw_degrees"),
        reload_seconds: num(&s, "reload_seconds"),
        ads_seconds: num(&s, "ads_seconds"),
        range: num(&s, "range"),
        // JSON numbers arrive as floats; capacities are whole rounds.
        magazine: num(&s, "magazine").map(|m| m.max(0.0).round() as u32),
        zoom: num(&s, "zoom"),
        magnification: num(&s, "magnification"),
        ergonomics: num(&s, "ergonomics").unwrap_or(0.0),
        weight: num(&s, "weight").unwrap_or(0.0),
        recoil_pct: num(&s, "recoil_pct").unwrap_or(0.0),
        spread_pct: num(&s, "spread_pct").unwrap_or(0.0),
        reload_pct: num(&s, "reload_pct").unwrap_or(0.0),
    };
    PartDef {
        id,
        slot,
        provides,
        stats,
    }
}

fn stats_to(s: &BuildStats) -> VarDictionary {
    let mut d = VarDictionary::new();
    let fields: [(&str, f64); 13] = [
        ("rounds_per_minute", s.rounds_per_minute),
        ("damage", s.damage),
        ("spread_degrees", s.spread_degrees),
        ("recoil_pitch_degrees", s.recoil_pitch_degrees),
        ("recoil_yaw_degrees", s.recoil_yaw_degrees),
        ("reload_seconds", s.reload_seconds),
        ("ads_seconds", s.ads_seconds),
        ("range", s.range),
        ("magazine", f64::from(s.magazine)),
        ("ads_zoom", s.zoom),
        ("magnification", s.magnification),
        ("ergonomics", s.ergonomics),
        ("weight", s.weight),
    ];
    for (key, value) in fields {
        put(&mut d, key, value.to_variant());
    }
    d
}
