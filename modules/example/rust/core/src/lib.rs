//! Pure rules for the example module. No Godot dependency, so `cargo test` covers it fast.

/// Doubles a value, saturating instead of overflowing.
pub fn double(value: i64) -> i64 {
    value.saturating_mul(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn doubles() {
        assert_eq!(double(21), 42);
    }

    #[test]
    fn saturates_instead_of_overflowing() {
        assert_eq!(double(i64::MAX), i64::MAX);
    }
}
