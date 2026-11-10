//! The server's save: one SQLite file holding each player's backpack, gun builds, health
//! and position, plus the world's loose loot and crate state. Plain tables, so the file can
//! be opened in any SQLite viewer to look or fix things by hand.
//!
//! Players are known by name. The first client to use a name leaves its key with it; later
//! joins under that name must bring the same key, so nobody takes a friend's gear by typing
//! their name.

use rusqlite::{Connection, OptionalExtension, params};
use std::collections::BTreeMap;

/// Bumped with every change to the tables; `open` upgrades older files step by step.
/// 2: items name the slot or grid they are in (`container`). 3: players have tokens.
pub const SCHEMA_VERSION: i64 = 3;
pub const MAX_NAME_CHARS: usize = 16;

#[derive(Debug, Clone, PartialEq)]
pub struct PlacedItem {
    pub item: String,
    /// Where it is: a grid ("pockets", "rig", "backpack") or a slot ("slot:rig").
    pub container: String,
    pub x: i64,
    pub y: i64,
    pub rotated: bool,
}

/// Weapon slot ("primary") -> part slot ("barrel") -> part id.
pub type Builds = BTreeMap<String, BTreeMap<String, String>>;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PlayerSave {
    pub health: f64,
    /// Mission pay, spent at the trader.
    pub tokens: i64,
    /// None for a player saved while dead: they start over at the spawn.
    pub position: Option<[f64; 3]>,
    pub items: Vec<PlacedItem>,
    pub builds: Builds,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LootSave {
    pub item: String,
    pub position: [f64; 3],
}

#[derive(Debug, Clone, PartialEq)]
pub struct CrateSave {
    /// The crate's place in spawn order; crates stand in the same spots every session.
    pub index: i64,
    pub items: Vec<String>,
    /// Seconds until an emptied crate refills, or None while it has something in it.
    pub refill_seconds: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct WorldSave {
    pub loot: Vec<LootSave>,
    pub crates: Vec<CrateSave>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Claim {
    /// Nobody had the name; it is this key's now.
    New,
    Returning,
    /// Someone else's name.
    WrongKey,
}

#[derive(Debug)]
pub enum Error {
    Sql(rusqlite::Error),
    /// The file was written by a newer game.
    TooNew(i64),
    BadName(&'static str),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Sql(e) => write!(f, "{e}"),
            Error::TooNew(v) => write!(
                f,
                "save is version {v}, this game reads up to {SCHEMA_VERSION}"
            ),
            Error::BadName(why) => f.write_str(why),
        }
    }
}

impl From<rusqlite::Error> for Error {
    fn from(e: rusqlite::Error) -> Self {
        Error::Sql(e)
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// A player name as typed, trimmed; refused if empty, too long, or with characters that
/// would look confusing next to other names.
pub fn clean_name(raw: &str) -> Result<String> {
    let name = raw.trim();
    if name.is_empty() {
        return Err(Error::BadName("name is empty"));
    }
    if name.chars().count() > MAX_NAME_CHARS {
        return Err(Error::BadName("name is longer than 16 characters"));
    }
    if !name
        .chars()
        .all(|c| c.is_alphanumeric() || c == ' ' || c == '_' || c == '-')
    {
        return Err(Error::BadName(
            "name may only use letters, digits, spaces, _ and -",
        ));
    }
    Ok(name.to_string())
}

pub struct Store {
    db: Connection,
}

impl Store {
    pub fn open(path: &str) -> Result<Store> {
        Store::setup(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Store> {
        Store::setup(Connection::open_in_memory()?)
    }

    fn setup(db: Connection) -> Result<Store> {
        // Another process (a second server on the same file) waits instead of failing.
        db.busy_timeout(std::time::Duration::from_secs(5))?;
        db.pragma_update(None, "foreign_keys", true)?;
        let version: i64 = db.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version > SCHEMA_VERSION {
            return Err(Error::TooNew(version));
        }
        if version < 1 {
            db.execute_batch(
                "BEGIN;
                CREATE TABLE players (
                    name TEXT PRIMARY KEY COLLATE NOCASE,
                    key TEXT NOT NULL,
                    health REAL NOT NULL DEFAULT 0,
                    x REAL, y REAL, z REAL,
                    first_seen INTEGER NOT NULL,
                    last_saved INTEGER NOT NULL
                );
                CREATE TABLE player_items (
                    player TEXT NOT NULL COLLATE NOCASE REFERENCES players(name) ON DELETE CASCADE,
                    item TEXT NOT NULL,
                    x INTEGER NOT NULL, y INTEGER NOT NULL,
                    rotated INTEGER NOT NULL
                );
                CREATE TABLE player_builds (
                    player TEXT NOT NULL COLLATE NOCASE REFERENCES players(name) ON DELETE CASCADE,
                    weapon_slot TEXT NOT NULL,
                    part_slot TEXT NOT NULL,
                    part TEXT NOT NULL,
                    PRIMARY KEY (player, weapon_slot, part_slot)
                );
                CREATE TABLE world (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE world_loot (
                    item TEXT NOT NULL,
                    x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL
                );
                CREATE TABLE crates (
                    idx INTEGER PRIMARY KEY,
                    refill_seconds REAL
                );
                CREATE TABLE crate_items (
                    crate INTEGER NOT NULL REFERENCES crates(idx) ON DELETE CASCADE,
                    item TEXT NOT NULL
                );
                PRAGMA user_version = 1;
                COMMIT;",
            )?;
        }
        if version < 2 {
            // Gear moved from one grid to slots and several grids; old saved items are
            // wiped rather than guessed into the new layout.
            db.execute_batch(
                "BEGIN;
                DELETE FROM player_items;
                ALTER TABLE player_items ADD COLUMN container TEXT NOT NULL DEFAULT '';
                PRAGMA user_version = 2;
                COMMIT;",
            )?;
        }
        if version < 3 {
            db.execute_batch(
                "BEGIN;
                ALTER TABLE players ADD COLUMN tokens INTEGER NOT NULL DEFAULT 0;
                PRAGMA user_version = 3;
                COMMIT;",
            )?;
        }
        Ok(Store { db })
    }

    /// Checks `name` against `key`, taking the name for this key if it is free. `now` is
    /// unix seconds.
    pub fn claim(&self, name: &str, key: &str, now: i64) -> Result<Claim> {
        let name = clean_name(name)?;
        let stored: Option<String> = self
            .db
            .query_row("SELECT key FROM players WHERE name = ?1", [&name], |r| {
                r.get(0)
            })
            .optional()?;
        match stored {
            Some(k) if k == key => Ok(Claim::Returning),
            Some(_) => Ok(Claim::WrongKey),
            None => {
                self.db.execute(
                    "INSERT INTO players (name, key, first_seen, last_saved) VALUES (?1, ?2, ?3, ?3)",
                    params![name, key, now],
                )?;
                Ok(Claim::New)
            }
        }
    }

    /// Replaces everything saved for a claimed player, all or nothing.
    pub fn save_player(&mut self, name: &str, save: &PlayerSave, now: i64) -> Result<()> {
        let tx = self.db.transaction()?;
        let [x, y, z] = match save.position {
            Some(p) => p.map(Some),
            None => [None; 3],
        };
        let changed = tx.execute(
            "UPDATE players SET health = ?2, x = ?3, y = ?4, z = ?5, last_saved = ?6, tokens = ?7 WHERE name = ?1",
            params![name, save.health, x, y, z, now, save.tokens],
        )?;
        if changed == 0 {
            // Never claimed: nothing to attach the rows to.
            return Err(Error::BadName("player was never claimed"));
        }
        tx.execute("DELETE FROM player_items WHERE player = ?1", [name])?;
        tx.execute("DELETE FROM player_builds WHERE player = ?1", [name])?;
        {
            let mut add = tx.prepare(
                "INSERT INTO player_items (player, item, x, y, rotated, container) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            for it in &save.items {
                add.execute(params![name, it.item, it.x, it.y, it.rotated, it.container])?;
            }
            let mut fit = tx.prepare(
                "INSERT INTO player_builds (player, weapon_slot, part_slot, part) VALUES (?1, ?2, ?3, ?4)",
            )?;
            for (weapon_slot, parts) in &save.builds {
                for (part_slot, part) in parts {
                    fit.execute(params![name, weapon_slot, part_slot, part])?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// What was saved for `name`, or None for a name never claimed.
    pub fn load_player(&self, name: &str) -> Result<Option<PlayerSave>> {
        let row = self
            .db
            .query_row(
                "SELECT health, x, y, z, tokens FROM players WHERE name = ?1",
                [name],
                |r| {
                    let health: f64 = r.get(0)?;
                    let x: Option<f64> = r.get(1)?;
                    let y: Option<f64> = r.get(2)?;
                    let z: Option<f64> = r.get(3)?;
                    let tokens: i64 = r.get(4)?;
                    Ok((health, x.zip(y).zip(z).map(|((x, y), z)| [x, y, z]), tokens))
                },
            )
            .optional()?;
        let Some((health, position, tokens)) = row else {
            return Ok(None);
        };
        let mut items_q = self.db.prepare(
            "SELECT item, x, y, rotated, container FROM player_items WHERE player = ?1 ORDER BY rowid",
        )?;
        let items = items_q
            .query_map([name], |r| {
                Ok(PlacedItem {
                    item: r.get(0)?,
                    x: r.get(1)?,
                    y: r.get(2)?,
                    rotated: r.get(3)?,
                    container: r.get(4)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut builds_q = self
            .db
            .prepare("SELECT weapon_slot, part_slot, part FROM player_builds WHERE player = ?1")?;
        let mut builds = Builds::new();
        for row in builds_q.query_map([name], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })? {
            let (weapon_slot, part_slot, part) = row?;
            builds
                .entry(weapon_slot)
                .or_default()
                .insert(part_slot, part);
        }
        Ok(Some(PlayerSave {
            health,
            tokens,
            position,
            items,
            builds,
        }))
    }

    /// Replaces the saved world, all or nothing.
    pub fn save_world(&mut self, world: &WorldSave, now: i64) -> Result<()> {
        let tx = self.db.transaction()?;
        tx.execute("DELETE FROM world_loot", [])?;
        tx.execute("DELETE FROM crates", [])?;
        {
            let mut loot =
                tx.prepare("INSERT INTO world_loot (item, x, y, z) VALUES (?1, ?2, ?3, ?4)")?;
            for l in &world.loot {
                let [x, y, z] = l.position;
                loot.execute(params![l.item, x, y, z])?;
            }
            let mut crate_row =
                tx.prepare("INSERT INTO crates (idx, refill_seconds) VALUES (?1, ?2)")?;
            let mut crate_item =
                tx.prepare("INSERT INTO crate_items (crate, item) VALUES (?1, ?2)")?;
            for c in &world.crates {
                crate_row.execute(params![c.index, c.refill_seconds])?;
                for item in &c.items {
                    crate_item.execute(params![c.index, item])?;
                }
            }
        }
        tx.execute(
            "INSERT INTO world (key, value) VALUES ('saved_at', ?1)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [now.to_string()],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// The saved world, or None if this file never had one (a fresh world).
    pub fn load_world(&self) -> Result<Option<WorldSave>> {
        let saved: Option<String> = self
            .db
            .query_row("SELECT value FROM world WHERE key = 'saved_at'", [], |r| {
                r.get(0)
            })
            .optional()?;
        if saved.is_none() {
            return Ok(None);
        }
        let mut loot_q = self
            .db
            .prepare("SELECT item, x, y, z FROM world_loot ORDER BY rowid")?;
        let loot = loot_q
            .query_map([], |r| {
                Ok(LootSave {
                    item: r.get(0)?,
                    position: [r.get(1)?, r.get(2)?, r.get(3)?],
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut crates_q = self
            .db
            .prepare("SELECT idx, refill_seconds FROM crates ORDER BY idx")?;
        let mut items_q = self
            .db
            .prepare("SELECT item FROM crate_items WHERE crate = ?1 ORDER BY rowid")?;
        let mut crates = Vec::new();
        for row in crates_q.query_map([], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, Option<f64>>(1)?))
        })? {
            let (index, refill_seconds) = row?;
            let items = items_q
                .query_map([index], |r| r.get(0))?
                .collect::<rusqlite::Result<Vec<String>>>()?;
            crates.push(CrateSave {
                index,
                items,
                refill_seconds,
            });
        }
        Ok(Some(WorldSave { loot, crates }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kit() -> PlayerSave {
        let mut builds = Builds::new();
        builds
            .entry("primary".into())
            .or_default()
            .insert("barrel".into(), "brl_long".into());
        builds
            .entry("primary".into())
            .or_default()
            .insert("receiver".into(), "rcv_ar".into());
        PlayerSave {
            health: 64.5,
            tokens: 420,
            position: Some([1.0, 2.5, -3.0]),
            items: vec![
                PlacedItem {
                    item: "medkit".into(),
                    container: "pockets".into(),
                    x: 0,
                    y: 0,
                    rotated: false,
                },
                PlacedItem {
                    item: "mag_30".into(),
                    container: "backpack".into(),
                    x: 3,
                    y: 1,
                    rotated: true,
                },
            ],
            builds,
        }
    }

    #[test]
    fn names_are_trimmed_and_checked() {
        assert_eq!(clean_name("  Allan ").unwrap(), "Allan");
        assert!(clean_name("   ").is_err());
        assert!(clean_name("a_name_way_too_long_x").is_err());
        assert!(clean_name("rm -rf; DROP").is_err());
        assert!(clean_name("Ørnen-2 _x").is_ok());
    }

    #[test]
    fn a_name_belongs_to_the_first_key() {
        let s = Store::open_in_memory().unwrap();
        assert_eq!(s.claim("Allan", "k1", 1).unwrap(), Claim::New);
        assert_eq!(s.claim("Allan", "k1", 2).unwrap(), Claim::Returning);
        assert_eq!(
            s.claim("allan", "k1", 2).unwrap(),
            Claim::Returning,
            "names ignore case"
        );
        assert_eq!(s.claim("Allan", "k2", 3).unwrap(), Claim::WrongKey);
    }

    #[test]
    fn a_player_comes_back_as_saved() {
        let mut s = Store::open_in_memory().unwrap();
        s.claim("Allan", "k", 1).unwrap();
        assert_eq!(s.load_player("Allan").unwrap(), Some(PlayerSave::default()));
        s.save_player("Allan", &kit(), 5).unwrap();
        assert_eq!(s.load_player("Allan").unwrap(), Some(kit()));
        assert_eq!(
            s.load_player("ALLAN").unwrap(),
            Some(kit()),
            "names ignore case"
        );
        // Saving again replaces, never appends.
        let mut less = kit();
        less.items.pop();
        less.position = None;
        s.save_player("Allan", &less, 6).unwrap();
        assert_eq!(s.load_player("Allan").unwrap(), Some(less));
    }

    #[test]
    fn unknown_players_are_not_saved_or_loaded() {
        let mut s = Store::open_in_memory().unwrap();
        assert_eq!(s.load_player("Nobody").unwrap(), None);
        assert!(s.save_player("Nobody", &kit(), 1).is_err());
    }

    #[test]
    fn a_fresh_world_has_no_save_until_one_is_written() {
        let mut s = Store::open_in_memory().unwrap();
        assert_eq!(s.load_world().unwrap(), None);
        let world = WorldSave {
            loot: vec![LootSave {
                item: "medkit".into(),
                position: [1.0, 0.5, 2.0],
            }],
            crates: vec![
                CrateSave {
                    index: 0,
                    items: vec!["mag_30".into(), "medkit".into()],
                    refill_seconds: None,
                },
                CrateSave {
                    index: 1,
                    items: vec![],
                    refill_seconds: Some(42.0),
                },
            ],
        };
        s.save_world(&world, 9).unwrap();
        assert_eq!(s.load_world().unwrap(), Some(world.clone()));
        let empty = WorldSave::default();
        s.save_world(&empty, 10).unwrap();
        assert_eq!(
            s.load_world().unwrap(),
            Some(empty),
            "an emptied world stays empty"
        );
    }

    #[test]
    fn the_file_survives_a_restart() {
        let dir =
            std::env::temp_dir().join(format!("slopocalypse-save-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("world.db");
        let path = path.to_str().unwrap();
        {
            let mut s = Store::open(path).unwrap();
            s.claim("Allan", "k", 1).unwrap();
            s.save_player("Allan", &kit(), 2).unwrap();
        }
        let s = Store::open(path).unwrap();
        assert_eq!(s.load_player("Allan").unwrap(), Some(kit()));
        drop(s);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_version_1_file_loses_its_items_but_keeps_players() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch(
            "CREATE TABLE players (name TEXT PRIMARY KEY COLLATE NOCASE, key TEXT NOT NULL,
                health REAL NOT NULL DEFAULT 0, x REAL, y REAL, z REAL,
                first_seen INTEGER NOT NULL, last_saved INTEGER NOT NULL);
            CREATE TABLE player_items (player TEXT NOT NULL, item TEXT NOT NULL,
                x INTEGER NOT NULL, y INTEGER NOT NULL, rotated INTEGER NOT NULL);
            INSERT INTO players (name, key, health, first_seen, last_saved) VALUES ('Allan', 'k', 50, 1, 1);
            INSERT INTO player_items VALUES ('Allan', 'medkit', 0, 0, 0);
            PRAGMA user_version = 1;",
        )
        .unwrap();
        let s = Store::setup(db).unwrap();
        assert_eq!(s.claim("Allan", "k", 2).unwrap(), Claim::Returning);
        let n: i64 =
            s.db.query_row("SELECT COUNT(*) FROM player_items", [], |r| r.get(0))
                .unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn a_newer_file_is_refused() {
        let db = Connection::open_in_memory().unwrap();
        db.pragma_update(None, "user_version", SCHEMA_VERSION + 1)
            .unwrap();
        assert!(matches!(Store::setup(db), Err(Error::TooNew(_))));
    }
}
