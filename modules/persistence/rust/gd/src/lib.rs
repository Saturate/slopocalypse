//! gdext binding for persistence_core: GDScript gets `SaveStore`, the server's save file.

// gdext's entry point must be an `unsafe impl` and its macro drops item-level allows, so
// binding crates allow unsafe at crate level. Pure crates keep it denied; keep logic there.
#![allow(unsafe_code)]

use godot::prelude::*;
use persistence_core::{
    Builds, Claim, CrateSave, LootSave, PlacedItem, PlayerSave, Store, WorldSave, clean_name,
};
use std::time::{SystemTime, UNIX_EPOCH};

struct PersistenceExtension;

#[gdextension]
unsafe impl ExtensionLibrary for PersistenceExtension {}

/// GDScript: `var s := SaveStore.new(); s.open(ProjectSettings.globalize_path(path))`.
/// Calls that can fail return false or an empty value and leave the reason in `last_error()`.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct SaveStore {
    store: Option<Store>,
    error: String,
    base: Base<RefCounted>,
}

#[godot_api]
impl SaveStore {
    /// Opens (or creates) the file at an OS path. "" opens a throwaway in-memory store.
    #[func]
    fn open(&mut self, path: GString) -> bool {
        let path = path.to_string();
        let opened = if path.is_empty() {
            Store::open_in_memory()
        } else {
            Store::open(&path)
        };
        match opened {
            Ok(s) => {
                self.store = Some(s);
                true
            }
            Err(e) => self.fail(e),
        }
    }

    #[func]
    fn last_error(&self) -> GString {
        GString::from(self.error.as_str())
    }

    /// The name as it will be stored, or "" if it is not allowed (reason in `last_error()`).
    #[func]
    fn clean_name(&mut self, name: GString) -> GString {
        match clean_name(&name.to_string()) {
            Ok(n) => GString::from(n.as_str()),
            Err(e) => {
                self.fail(e);
                GString::new()
            }
        }
    }

    /// "new", "returning" or "wrong_key"; "" on failure.
    #[func]
    fn claim(&mut self, name: GString, key: GString) -> GString {
        let Some(store) = self.store.as_ref() else {
            return self.closed_str();
        };
        match store.claim(&name.to_string(), &key.to_string(), now()) {
            Ok(Claim::New) => "new".into(),
            Ok(Claim::Returning) => "returning".into(),
            Ok(Claim::WrongKey) => "wrong_key".into(),
            Err(e) => {
                self.fail(e);
                GString::new()
            }
        }
    }

    /// `save` is `{health, tokens, position: Vector3 or null, items: [{item, container, x, y, rotated}],
    /// builds: {weapon_slot: {part_slot: part}}}`.
    #[func]
    fn save_player(&mut self, name: GString, save: VarDictionary) -> bool {
        let player = player_from(&save);
        let Some(store) = self.store.as_mut() else {
            return self.closed();
        };
        match store.save_player(&name.to_string(), &player, now()) {
            Ok(()) => true,
            Err(e) => self.fail(e),
        }
    }

    /// The same shape `save_player` takes, or `{}` for a name never seen.
    #[func]
    fn load_player(&mut self, name: GString) -> VarDictionary {
        let Some(store) = self.store.as_ref() else {
            self.closed();
            return VarDictionary::new();
        };
        match store.load_player(&name.to_string()) {
            Ok(Some(p)) => player_to(&p),
            Ok(None) => VarDictionary::new(),
            Err(e) => {
                self.fail(e);
                VarDictionary::new()
            }
        }
    }

    /// `world` is `{loot: [{item, position}], crates: [{index, items, refill_seconds}]}`;
    /// a negative refill_seconds means the crate is not waiting to refill.
    #[func]
    fn save_world(&mut self, world: VarDictionary) -> bool {
        let w = world_from(&world);
        let Some(store) = self.store.as_mut() else {
            return self.closed();
        };
        match store.save_world(&w, now()) {
            Ok(()) => true,
            Err(e) => self.fail(e),
        }
    }

    /// The same shape `save_world` takes, or `{}` if no world was ever saved here.
    #[func]
    fn load_world(&mut self) -> VarDictionary {
        let Some(store) = self.store.as_ref() else {
            self.closed();
            return VarDictionary::new();
        };
        match store.load_world() {
            Ok(Some(w)) => world_to(&w),
            Ok(None) => VarDictionary::new(),
            Err(e) => {
                self.fail(e);
                VarDictionary::new()
            }
        }
    }
}

impl SaveStore {
    fn fail(&mut self, e: impl std::fmt::Display) -> bool {
        self.error = e.to_string();
        false
    }

    fn closed(&mut self) -> bool {
        self.fail("save store is not open")
    }

    fn closed_str(&mut self) -> GString {
        self.closed();
        GString::new()
    }
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX))
}

fn num(d: &VarDictionary, key: &str) -> f64 {
    let v = d.get_or_nil(key);
    v.try_to::<f64>()
        .or_else(|_| v.try_to::<i64>().map(|i| i as f64))
        .unwrap_or(0.0)
}

fn text(d: &VarDictionary, key: &str) -> String {
    d.get_or_nil(key)
        .try_to::<GString>()
        .map(|s| s.to_string())
        .unwrap_or_default()
}

fn dicts(d: &VarDictionary, key: &str) -> Vec<VarDictionary> {
    d.get_or_nil(key)
        .try_to::<VarArray>()
        .map(|a| {
            a.iter_shared()
                .filter_map(|v| v.try_to::<VarDictionary>().ok())
                .collect()
        })
        .unwrap_or_default()
}

fn vec3(v: &Variant) -> Option<[f64; 3]> {
    v.try_to::<Vector3>()
        .ok()
        .map(|p| [f64::from(p.x), f64::from(p.y), f64::from(p.z)])
}

fn to_vec3(p: [f64; 3]) -> Vector3 {
    Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32)
}

fn player_from(d: &VarDictionary) -> PlayerSave {
    let items = dicts(d, "items")
        .iter()
        .map(|i| PlacedItem {
            item: text(i, "item"),
            container: text(i, "container"),
            x: num(i, "x") as i64,
            y: num(i, "y") as i64,
            rotated: i.get_or_nil("rotated").try_to::<bool>().unwrap_or(false),
        })
        .collect();
    let mut builds = Builds::new();
    if let Ok(all) = d.get_or_nil("builds").try_to::<VarDictionary>() {
        for (weapon_slot, parts) in all.iter_shared() {
            let (Ok(weapon_slot), Ok(parts)) = (
                weapon_slot.try_to::<GString>(),
                parts.try_to::<VarDictionary>(),
            ) else {
                continue;
            };
            let entry = builds.entry(weapon_slot.to_string()).or_default();
            for (part_slot, part) in parts.iter_shared() {
                if let (Ok(s), Ok(p)) = (part_slot.try_to::<GString>(), part.try_to::<GString>()) {
                    entry.insert(s.to_string(), p.to_string());
                }
            }
        }
    }
    PlayerSave {
        health: num(d, "health"),
        tokens: num(d, "tokens") as i64,
        position: vec3(&d.get_or_nil("position")),
        items,
        builds,
    }
}

fn player_to(p: &PlayerSave) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("health", p.health);
    d.set("tokens", p.tokens);
    match p.position {
        Some(pos) => d.set("position", to_vec3(pos)),
        None => d.set("position", &Variant::nil()),
    }
    let mut items = VarArray::new();
    for it in &p.items {
        let mut i = VarDictionary::new();
        i.set("item", it.item.as_str());
        i.set("container", it.container.as_str());
        i.set("x", it.x);
        i.set("y", it.y);
        i.set("rotated", it.rotated);
        items.push(&i.to_variant());
    }
    d.set("items", &items);
    let mut builds = VarDictionary::new();
    for (weapon_slot, parts) in &p.builds {
        let mut b = VarDictionary::new();
        for (part_slot, part) in parts {
            b.set(part_slot.as_str(), part.as_str());
        }
        builds.set(weapon_slot.as_str(), &b);
    }
    d.set("builds", &builds);
    d
}

fn world_from(d: &VarDictionary) -> WorldSave {
    WorldSave {
        loot: dicts(d, "loot")
            .iter()
            .filter_map(|l| {
                Some(LootSave {
                    item: text(l, "item"),
                    position: vec3(&l.get_or_nil("position"))?,
                })
            })
            .collect(),
        crates: dicts(d, "crates")
            .iter()
            .map(|c| {
                let refill = num(c, "refill_seconds");
                CrateSave {
                    index: num(c, "index") as i64,
                    items: c
                        .get_or_nil("items")
                        .try_to::<VarArray>()
                        .map(|a| {
                            a.iter_shared()
                                .filter_map(|v| v.try_to::<GString>().ok())
                                .map(|s| s.to_string())
                                .collect()
                        })
                        .unwrap_or_default(),
                    refill_seconds: (refill >= 0.0 && c.contains_key("refill_seconds"))
                        .then_some(refill),
                }
            })
            .collect(),
    }
}

fn world_to(w: &WorldSave) -> VarDictionary {
    let mut loot = VarArray::new();
    for l in &w.loot {
        let mut d = VarDictionary::new();
        d.set("item", l.item.as_str());
        d.set("position", to_vec3(l.position));
        loot.push(&d.to_variant());
    }
    let mut crates = VarArray::new();
    for c in &w.crates {
        let mut d = VarDictionary::new();
        d.set("index", c.index);
        let mut items = VarArray::new();
        for item in &c.items {
            items.push(&GString::from(item.as_str()).to_variant());
        }
        d.set("items", &items);
        d.set("refill_seconds", c.refill_seconds.unwrap_or(-1.0));
        crates.push(&d.to_variant());
    }
    let mut out = VarDictionary::new();
    out.set("loot", &loot);
    out.set("crates", &crates);
    out
}
