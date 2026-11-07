//! Guns assembled from parts in slots, Tarkov style: a receiver provides slots (barrel,
//! stock, optic ...), some parts provide more (a barrel provides the muzzle slot), and
//! every part changes the final stats. Pure rules over data so server and clients agree.

use std::collections::BTreeMap;

/// Slots every working gun needs filled.
pub const REQUIRED_SLOTS: [&str; 4] = ["receiver", "barrel", "grip", "magazine"];
/// Ergonomics that leaves the receiver's ADS time unchanged; more is faster.
pub const NEUTRAL_ERGONOMICS: f64 = 50.0;

/// What one part changes. Base values (`Some`) replace the gun's value and come from the
/// part that owns them (receiver: fire rate, damage, spread, recoil, reload, ADS time;
/// barrel: range; magazine: capacity; optic: zoom and magnification). The rest add up
/// across all parts.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct PartStats {
    pub rounds_per_minute: Option<f64>,
    pub damage: Option<f64>,
    pub spread_degrees: Option<f64>,
    pub recoil_pitch_degrees: Option<f64>,
    pub recoil_yaw_degrees: Option<f64>,
    pub reload_seconds: Option<f64>,
    pub ads_seconds: Option<f64>,
    pub range: Option<f64>,
    pub magazine: Option<u32>,
    /// How much the main view zooms while aiming (red dots: a little).
    pub zoom: Option<f64>,
    /// How much a scope's lens magnifies, seen picture in picture; 1 for open sights.
    pub magnification: Option<f64>,
    pub ergonomics: f64,
    pub weight: f64,
    /// Percent changes, summed over parts: -10 means 10% less.
    pub recoil_pct: f64,
    pub spread_pct: f64,
    pub reload_pct: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PartDef {
    pub id: String,
    pub slot: String,
    /// Slots this part makes available for other parts.
    pub provides: Vec<String>,
    pub stats: PartStats,
}

/// The finished gun's numbers.
#[derive(Debug, Clone, PartialEq)]
pub struct BuildStats {
    pub rounds_per_minute: f64,
    pub damage: f64,
    pub spread_degrees: f64,
    pub recoil_pitch_degrees: f64,
    pub recoil_yaw_degrees: f64,
    pub reload_seconds: f64,
    pub ads_seconds: f64,
    pub range: f64,
    pub magazine: u32,
    pub zoom: f64,
    pub magnification: f64,
    pub ergonomics: f64,
    pub weight: f64,
}

/// Why a build is not a working gun.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BuildError {
    UnknownPart {
        slot: String,
        part: String,
    },
    WrongSlot {
        slot: String,
        part: String,
        fits: String,
    },
    SlotNotProvided {
        slot: String,
    },
    Missing {
        slot: String,
    },
}

impl std::fmt::Display for BuildError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownPart { slot, part } => write!(f, "{slot}: unknown part '{part}'"),
            Self::WrongSlot { slot, part, fits } => {
                write!(f, "{slot}: '{part}' fits the {fits} slot")
            }
            Self::SlotNotProvided { slot } => {
                write!(f, "{slot}: nothing fitted provides this slot")
            }
            Self::Missing { slot } => write!(f, "{slot}: required and empty"),
        }
    }
}

/// Checks a build (slot -> part id) against the catalogue and computes its stats. Every
/// problem is reported, not just the first, so a modding screen can show them all.
pub fn assemble(
    catalogue: &BTreeMap<String, PartDef>,
    build: &BTreeMap<String, String>,
) -> Result<BuildStats, Vec<BuildError>> {
    let mut errors = Vec::new();
    let mut fitted: Vec<&PartDef> = Vec::new();
    for (slot, part_id) in build {
        match catalogue.get(part_id) {
            None => errors.push(BuildError::UnknownPart {
                slot: slot.clone(),
                part: part_id.clone(),
            }),
            Some(part) if &part.slot != slot => errors.push(BuildError::WrongSlot {
                slot: slot.clone(),
                part: part_id.clone(),
                fits: part.slot.clone(),
            }),
            Some(part) => fitted.push(part),
        }
    }
    // The receiver is the root; every other slot must be provided by a fitted part.
    for part in &fitted {
        if part.slot != "receiver" && !fitted.iter().any(|p| p.provides.contains(&part.slot)) {
            errors.push(BuildError::SlotNotProvided {
                slot: part.slot.clone(),
            });
        }
    }
    for slot in REQUIRED_SLOTS {
        if !build.contains_key(slot) {
            errors.push(BuildError::Missing {
                slot: slot.to_string(),
            });
        }
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    Ok(combine(&fitted))
}

fn combine(parts: &[&PartDef]) -> BuildStats {
    let base = |pick: fn(&PartStats) -> Option<f64>, default: f64| {
        parts.iter().find_map(|p| pick(&p.stats)).unwrap_or(default)
    };
    let sum = |pick: fn(&PartStats) -> f64| parts.iter().map(|p| pick(&p.stats)).sum::<f64>();
    // Percent modifiers never take a value below a fifth of its base.
    let scale = |pct: f64| (1.0 + pct / 100.0).max(0.2);
    let ergonomics = sum(|s| s.ergonomics);
    let recoil = scale(sum(|s| s.recoil_pct));
    // Each point of ergonomics away from neutral changes ADS time by 1%, within 0.5x..2x.
    let ads_factor = (1.0 + (NEUTRAL_ERGONOMICS - ergonomics) / 100.0).clamp(0.5, 2.0);
    BuildStats {
        rounds_per_minute: base(|s| s.rounds_per_minute, 600.0),
        damage: base(|s| s.damage, 0.0),
        spread_degrees: base(|s| s.spread_degrees, 1.0) * scale(sum(|s| s.spread_pct)),
        recoil_pitch_degrees: base(|s| s.recoil_pitch_degrees, 1.0) * recoil,
        recoil_yaw_degrees: base(|s| s.recoil_yaw_degrees, 0.3) * recoil,
        reload_seconds: base(|s| s.reload_seconds, 2.0) * scale(sum(|s| s.reload_pct)),
        ads_seconds: base(|s| s.ads_seconds, 0.2) * ads_factor,
        range: base(|s| s.range, 100.0),
        magazine: parts.iter().find_map(|p| p.stats.magazine).unwrap_or(0),
        zoom: base(|s| s.zoom, 1.0),
        magnification: base(|s| s.magnification, 1.0),
        ergonomics,
        weight: sum(|s| s.weight),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn part(id: &str, slot: &str, provides: &[&str], stats: PartStats) -> (String, PartDef) {
        let def = PartDef {
            id: id.into(),
            slot: slot.into(),
            provides: provides.iter().map(|s| s.to_string()).collect(),
            stats,
        };
        (id.into(), def)
    }

    fn catalogue() -> BTreeMap<String, PartDef> {
        BTreeMap::from([
            part(
                "rcv",
                "receiver",
                &["barrel", "grip", "magazine", "stock", "optic"],
                PartStats {
                    rounds_per_minute: Some(650.0),
                    damage: Some(25.0),
                    spread_degrees: Some(0.6),
                    recoil_pitch_degrees: Some(1.0),
                    recoil_yaw_degrees: Some(0.4),
                    reload_seconds: Some(2.0),
                    ads_seconds: Some(0.2),
                    ergonomics: 30.0,
                    weight: 1.2,
                    ..Default::default()
                },
            ),
            part(
                "barrel_long",
                "barrel",
                &["muzzle"],
                PartStats {
                    range: Some(300.0),
                    weight: 0.7,
                    ..Default::default()
                },
            ),
            part(
                "barrel_short",
                "barrel",
                &["muzzle"],
                PartStats {
                    range: Some(180.0),
                    spread_pct: 40.0,
                    ergonomics: 8.0,
                    weight: 0.45,
                    ..Default::default()
                },
            ),
            part(
                "grip",
                "grip",
                &[],
                PartStats {
                    ergonomics: 10.0,
                    weight: 0.1,
                    ..Default::default()
                },
            ),
            part(
                "mag30",
                "magazine",
                &[],
                PartStats {
                    magazine: Some(30),
                    weight: 0.4,
                    ..Default::default()
                },
            ),
            part(
                "mag45",
                "magazine",
                &[],
                PartStats {
                    magazine: Some(45),
                    ergonomics: -8.0,
                    reload_pct: 15.0,
                    weight: 0.6,
                    ..Default::default()
                },
            ),
            part(
                "comp",
                "muzzle",
                &[],
                PartStats {
                    recoil_pct: -12.0,
                    weight: 0.1,
                    ..Default::default()
                },
            ),
            part(
                "stock",
                "stock",
                &[],
                PartStats {
                    recoil_pct: -20.0,
                    ergonomics: 10.0,
                    weight: 0.3,
                    ..Default::default()
                },
            ),
            part(
                "dot",
                "optic",
                &[],
                PartStats {
                    zoom: Some(1.25),
                    weight: 0.15,
                    ..Default::default()
                },
            ),
            part(
                "scope",
                "optic",
                &[],
                PartStats {
                    zoom: Some(1.1),
                    magnification: Some(4.0),
                    weight: 0.5,
                    ..Default::default()
                },
            ),
        ])
    }

    fn build(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(s, p)| (s.to_string(), p.to_string()))
            .collect()
    }

    fn standard() -> BTreeMap<String, String> {
        build(&[
            ("receiver", "rcv"),
            ("barrel", "barrel_long"),
            ("grip", "grip"),
            ("magazine", "mag30"),
            ("stock", "stock"),
        ])
    }

    #[test]
    fn a_complete_build_gets_its_base_stats_from_the_owning_parts() {
        let stats = assemble(&catalogue(), &standard()).expect("valid");
        assert_eq!(stats.rounds_per_minute, 650.0);
        assert_eq!(stats.damage, 25.0);
        assert_eq!(stats.range, 300.0);
        assert_eq!(stats.magazine, 30);
        assert_eq!(stats.zoom, 1.0);
        assert!((stats.weight - 2.7).abs() < 1e-9);
    }

    #[test]
    fn percent_modifiers_add_up_before_they_scale() {
        let mut b = standard();
        b.insert("muzzle".into(), "comp".into());
        let stats = assemble(&catalogue(), &b).expect("valid");
        // Stock -20% and compensator -12% make -32%.
        assert!((stats.recoil_pitch_degrees - 0.68).abs() < 1e-9);
        assert!((stats.recoil_yaw_degrees - 0.4 * 0.68).abs() < 1e-9);
    }

    #[test]
    fn a_bigger_magazine_holds_more_but_handles_worse() {
        let mut b = standard();
        b.insert("magazine".into(), "mag45".into());
        let big = assemble(&catalogue(), &b).expect("valid");
        let small = assemble(&catalogue(), &standard()).expect("valid");
        assert_eq!(big.magazine, 45);
        assert!(big.reload_seconds > small.reload_seconds);
        assert!(big.ads_seconds > small.ads_seconds);
    }

    #[test]
    fn a_short_barrel_trades_range_and_spread_for_ergonomics() {
        let mut b = standard();
        b.insert("barrel".into(), "barrel_short".into());
        let short = assemble(&catalogue(), &b).expect("valid");
        let long = assemble(&catalogue(), &standard()).expect("valid");
        assert!(short.range < long.range);
        assert!(short.spread_degrees > long.spread_degrees);
        assert!(short.ads_seconds < long.ads_seconds);
    }

    #[test]
    fn ergonomics_set_ads_time_around_neutral() {
        // rcv 30 + grip 10 + stock 10 = 50, neutral: the receiver's own ADS time.
        let stats = assemble(&catalogue(), &standard()).expect("valid");
        assert!((stats.ads_seconds - 0.2).abs() < 1e-9);
    }

    #[test]
    fn open_sights_do_not_magnify_and_a_scope_does() {
        let mut b = standard();
        b.insert("optic".into(), "dot".into());
        assert_eq!(
            assemble(&catalogue(), &b).expect("valid").magnification,
            1.0
        );
        b.insert("optic".into(), "scope".into());
        let stats = assemble(&catalogue(), &b).expect("valid");
        assert_eq!(stats.magnification, 4.0);
        assert_eq!(stats.zoom, 1.1);
    }

    #[test]
    fn an_optic_sets_the_zoom() {
        let mut b = standard();
        b.insert("optic".into(), "dot".into());
        assert_eq!(assemble(&catalogue(), &b).expect("valid").zoom, 1.25);
    }

    #[test]
    fn a_muzzle_needs_a_barrel_to_mount_on() {
        let mut b = standard();
        b.remove("barrel");
        b.insert("muzzle".into(), "comp".into());
        let errors = assemble(&catalogue(), &b).expect_err("invalid");
        assert!(errors.contains(&BuildError::SlotNotProvided {
            slot: "muzzle".into()
        }));
        assert!(errors.contains(&BuildError::Missing {
            slot: "barrel".into()
        }));
    }

    #[test]
    fn parts_only_fit_their_own_slot() {
        let mut b = standard();
        b.insert("stock".into(), "mag30".into());
        let errors = assemble(&catalogue(), &b).expect_err("invalid");
        assert_eq!(
            errors,
            vec![BuildError::WrongSlot {
                slot: "stock".into(),
                part: "mag30".into(),
                fits: "magazine".into()
            }]
        );
    }

    #[test]
    fn unknown_parts_and_every_problem_are_reported() {
        let b = build(&[("receiver", "rcv"), ("barrel", "laser_cannon")]);
        let errors = assemble(&catalogue(), &b).expect_err("invalid");
        assert!(errors.contains(&BuildError::UnknownPart {
            slot: "barrel".into(),
            part: "laser_cannon".into()
        }));
        assert!(errors.contains(&BuildError::Missing {
            slot: "grip".into()
        }));
        assert!(errors.contains(&BuildError::Missing {
            slot: "magazine".into()
        }));
    }
}
