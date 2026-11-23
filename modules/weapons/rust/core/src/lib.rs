//! Fire rules for hitscan weapons: rate of fire, magazine, reload, the action that readies
//! the next round, and seeded spread.
//! Pure Rust so the server and every client compute identical results, and so the rules are
//! covered by fast `cargo test` without the engine.

pub mod parts;

/// Static stats for one weapon, loaded from data by the caller.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WeaponStats {
    pub rounds_per_minute: f64,
    pub magazine: u32,
    pub reload_seconds: f64,
    /// Half-angle of the spread cone, in radians.
    pub spread_radians: f64,
    pub action: Action,
}

/// How the next round gets into the chamber after a shot.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Action {
    /// The gun does it itself; only the rate of fire limits the next shot.
    SelfLoading,
    /// Someone works the bolt after every shot, which takes `cycle_seconds`. A reload
    /// chambers a round too, so the last shot of a magazine needs no cycle.
    Manual { cycle_seconds: f64 },
}

/// Mutable state of one weapon instance.
#[derive(Debug, Clone)]
pub struct WeaponState {
    stats: WeaponStats,
    ammo: u32,
    cooldown: f64,
    reload_left: Option<f64>,
    /// Time left working the bolt; `Some` while the chamber is empty after a shot.
    cycle_left: Option<f64>,
    rng: SplitMix64,
    last_spread: (f64, f64),
}

/// Why a shot did not happen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Blocked {
    Cooldown,
    Empty,
    Reloading,
    /// A manual action: the bolt has not been worked since the last shot.
    Cycling,
}

impl WeaponState {
    pub fn new(stats: WeaponStats, seed: u64) -> Self {
        Self {
            stats,
            ammo: stats.magazine,
            cooldown: 0.0,
            reload_left: None,
            cycle_left: None,
            rng: SplitMix64::new(seed),
            last_spread: (0.0, 0.0),
        }
    }

    pub fn ammo(&self) -> u32 {
        self.ammo
    }

    pub fn is_reloading(&self) -> bool {
        self.reload_left.is_some()
    }

    pub fn is_cycling(&self) -> bool {
        self.cycle_left.is_some()
    }

    /// Spread of the last shot as (yaw, pitch) offsets in radians.
    pub fn last_spread(&self) -> (f64, f64) {
        self.last_spread
    }

    /// Advances timers. Call once per physics tick.
    pub fn tick(&mut self, delta: f64) {
        self.cooldown = (self.cooldown - delta).max(0.0);
        self.cycle_left = self
            .cycle_left
            .map(|left| left - delta)
            .filter(|&left| left > 0.0);
        if let Some(left) = self.reload_left {
            let left = left - delta;
            if left <= 0.0 {
                self.reload_left = None;
                self.ammo = self.stats.magazine;
            } else {
                self.reload_left = Some(left);
            }
        }
    }

    pub fn try_fire(&mut self) -> Result<(f64, f64), Blocked> {
        if self.reload_left.is_some() {
            return Err(Blocked::Reloading);
        }
        if self.ammo == 0 {
            return Err(Blocked::Empty);
        }
        if self.cycle_left.is_some() {
            return Err(Blocked::Cycling);
        }
        if self.cooldown > 0.0 {
            return Err(Blocked::Cooldown);
        }
        self.ammo -= 1;
        self.cooldown = 60.0 / self.stats.rounds_per_minute;
        if let Action::Manual { cycle_seconds } = self.stats.action
            && self.ammo > 0
            && cycle_seconds > 0.0
        {
            self.cycle_left = Some(cycle_seconds);
        }
        self.last_spread = self.next_spread();
        Ok(self.last_spread)
    }

    /// Starts a reload. Returns false when already reloading or the magazine is full.
    pub fn start_reload(&mut self) -> bool {
        if self.reload_left.is_some() || self.ammo == self.stats.magazine {
            return false;
        }
        self.reload_left = Some(self.stats.reload_seconds);
        // Reloading replaces working the bolt: the reload chambers a round itself.
        self.cycle_left = None;
        true
    }

    /// Empties the magazine and reloads, as after swapping parts: the new gun is only
    /// ready once a full reload has passed, so a swap is never a free top-up.
    pub fn start_empty_reload(&mut self) {
        self.ammo = 0;
        self.reload_left = Some(self.stats.reload_seconds);
        self.cycle_left = None;
    }

    /// Uniform over the cone's disc, not its square, so corners aren't favoured.
    fn next_spread(&mut self) -> (f64, f64) {
        let r = self.stats.spread_radians * self.rng.next_unit().sqrt();
        let angle = std::f64::consts::TAU * self.rng.next_unit();
        (r * angle.cos(), r * angle.sin())
    }
}

/// Small, well-known deterministic generator; avoids a dependency for a few random numbers.
#[derive(Debug, Clone)]
struct SplitMix64(u64);

impl SplitMix64 {
    fn new(seed: u64) -> Self {
        Self(seed)
    }

    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    fn next_unit(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rifle() -> WeaponStats {
        WeaponStats {
            rounds_per_minute: 600.0,
            magazine: 30,
            reload_seconds: 2.0,
            spread_radians: 0.01,
            action: Action::SelfLoading,
        }
    }

    fn bolt_action() -> WeaponStats {
        WeaponStats {
            rounds_per_minute: 300.0,
            magazine: 5,
            reload_seconds: 3.0,
            spread_radians: 0.002,
            action: Action::Manual { cycle_seconds: 1.0 },
        }
    }

    #[test]
    fn manual_cycle_blocks_the_next_shot_until_cycled() {
        let mut w = WeaponState::new(bolt_action(), 1);
        assert!(w.try_fire().is_ok());
        assert!(w.is_cycling());
        // Long past the rate of fire's 0.2 s, still inside the cycle.
        w.tick(0.5);
        assert_eq!(w.try_fire(), Err(Blocked::Cycling));
        w.tick(0.49);
        assert_eq!(w.try_fire(), Err(Blocked::Cycling));
        w.tick(0.02);
        assert!(!w.is_cycling());
        assert!(w.try_fire().is_ok());
        assert_eq!(w.ammo(), 3);
    }

    #[test]
    fn a_self_loading_gun_never_cycles() {
        let mut w = WeaponState::new(rifle(), 1);
        w.try_fire().unwrap();
        assert!(!w.is_cycling());
    }

    #[test]
    fn the_last_round_leaves_nothing_to_cycle() {
        let mut w = WeaponState::new(bolt_action(), 1);
        for _ in 0..5 {
            w.try_fire().unwrap();
            w.tick(1.01);
        }
        assert_eq!(w.ammo(), 0);
        w.try_fire().unwrap_err();
        assert!(!w.is_cycling());
    }

    #[test]
    fn an_empty_reload_after_a_part_swap_drops_the_cycle() {
        let mut w = WeaponState::new(bolt_action(), 1);
        w.try_fire().unwrap();
        assert!(w.is_cycling());
        w.start_empty_reload();
        assert!(!w.is_cycling());
        w.tick(3.01);
        assert!(w.try_fire().is_ok());
    }

    #[test]
    fn a_reload_chambers_a_round_instead_of_the_bolt() {
        let mut w = WeaponState::new(bolt_action(), 1);
        w.try_fire().unwrap();
        assert!(w.start_reload());
        assert!(!w.is_cycling());
        w.tick(3.01);
        assert_eq!(w.ammo(), 5);
        assert!(w.try_fire().is_ok());
    }

    #[test]
    fn rate_of_fire_follows_rpm() {
        let mut w = WeaponState::new(rifle(), 1);
        assert!(w.try_fire().is_ok());
        assert_eq!(w.try_fire(), Err(Blocked::Cooldown));
        w.tick(0.099);
        assert_eq!(w.try_fire(), Err(Blocked::Cooldown));
        w.tick(0.002);
        assert!(w.try_fire().is_ok());
    }

    #[test]
    fn magazine_empties_then_blocks() {
        let mut w = WeaponState::new(rifle(), 1);
        for _ in 0..30 {
            assert!(w.try_fire().is_ok());
            w.tick(0.1);
        }
        assert_eq!(w.ammo(), 0);
        assert_eq!(w.try_fire(), Err(Blocked::Empty));
    }

    #[test]
    fn reload_takes_its_time_then_refills() {
        let mut w = WeaponState::new(rifle(), 1);
        w.try_fire().unwrap();
        assert!(w.start_reload());
        assert_eq!(w.try_fire(), Err(Blocked::Reloading));
        w.tick(1.9);
        assert!(w.is_reloading());
        w.tick(0.2);
        assert!(!w.is_reloading());
        assert_eq!(w.ammo(), 30);
    }

    #[test]
    fn no_reload_with_a_full_magazine() {
        let mut w = WeaponState::new(rifle(), 1);
        assert!(!w.start_reload());
    }

    #[test]
    fn spread_stays_inside_the_cone() {
        let mut w = WeaponState::new(rifle(), 7);
        for _ in 0..1000 {
            let (yaw, pitch) = w.next_spread();
            assert!((yaw * yaw + pitch * pitch).sqrt() <= 0.01 + 1e-12);
        }
    }

    #[test]
    fn same_seed_gives_same_spread() {
        let mut a = WeaponState::new(rifle(), 42);
        let mut b = WeaponState::new(rifle(), 42);
        for _ in 0..10 {
            assert_eq!(a.try_fire(), b.try_fire());
            a.tick(0.1);
            b.tick(0.1);
        }
    }

    #[test]
    fn different_seeds_give_different_spread() {
        let mut a = WeaponState::new(rifle(), 1);
        let mut b = WeaponState::new(rifle(), 2);
        assert_ne!(a.try_fire(), b.try_fire());
    }

    #[test]
    fn an_empty_reload_blocks_firing_until_it_finishes() {
        let mut w = WeaponState::new(rifle(), 1);
        w.start_empty_reload();
        assert!(w.try_fire().is_err());
        w.tick(rifle().reload_seconds + 0.01);
        assert_eq!(w.ammo(), rifle().magazine);
        assert!(w.try_fire().is_ok());
    }
}
