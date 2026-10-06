//! The recovery code: 128 random bits written on a card in the glovebox,
//! which attaches a new device key to the account.
//!
//! Display: the bits in Crockford base32 (26 symbols), then one check
//! symbol, in groups of four: `3QDT-8Y0K-...-W2Q`. The check symbol (Luhn
//! mod 32) catches any single mistyped symbol and most swaps of two
//! neighbours before a person spends one of the five attempts an hour the
//! server allows; its cost is one symbol. Reading is tolerant: case,
//! spaces and hyphens do not matter, and `O`, `I` and `L` are read as the
//! digits they look like, as Crockford's alphabet intends.

use argon2::{Algorithm, Argon2, Params, Version};

use crate::{AuthError, random};

/// Crockford's base32 alphabet: digits and capitals without I, L, O and U,
/// which are read as 1, 1, 0 and refused.
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/// Symbols of the 128 bits: 26 of 5 bits, the first one carrying 3.
const DATA_SYMBOLS: usize = 26;

/// Symbols of a code: the data and the check symbol.
pub const RECOVERY_SYMBOLS: usize = DATA_SYMBOLS + 1;

/// Symbols per group in the displayed form.
const GROUP: usize = 4;

/// Longest text `parse` looks at: the displayed form is 33 characters, so
/// anything far longer is not a code.
const MAX_INPUT_CHARS: usize = 100;

/// The salt of every recovery hash. A fixed salt is sound here because the
/// code is 128 uniformly random bits, not a password: a salt exists to stop
/// one precomputed table from serving many guesses of low-entropy secrets,
/// and no table can cover 2^128 values. It is what lets the server find an
/// account from a code alone, by its hash, with one argon2id computation per
/// attempt instead of one per account. argon2id itself makes each guess
/// against a stolen database cost about as much as on the server.
const SALT: &[u8] = b"lunaway-recovery-v1";

/// argon2id memory in KiB, passes and lanes: OWASP's first recommended
/// setting (19 MiB, 2 passes, 1 lane).
const MEMORY_KIB: u32 = 19 * 1024;
const PASSES: u32 = 2;
const LANES: u32 = 1;

/// A recovery code: 128 random bits. Its `Debug` form never shows them.
#[derive(Clone, PartialEq, Eq)]
pub struct RecoveryCode([u8; 16]);

impl std::fmt::Debug for RecoveryCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("RecoveryCode(..)")
    }
}

fn symbol_value(c: char) -> Option<u8> {
    let c = match c.to_ascii_uppercase() {
        'O' => '0',
        'I' | 'L' => '1',
        other => other,
    };
    ALPHABET
        .iter()
        .position(|&a| char::from(a) == c)
        .and_then(|p| u8::try_from(p).ok())
}

/// The Luhn mod 32 check value of `symbols` (values 0 to 31): the value that
/// makes the sum over symbols and check a multiple of 32.
fn check_value(symbols: &[u8]) -> u8 {
    let mut sum: u32 = 0;
    // The rightmost data symbol is doubled, as in the decimal Luhn
    // algorithm, the check symbol to its right being the undoubled one.
    for (i, &v) in symbols.iter().rev().enumerate() {
        let addend = u32::from(v) * if i % 2 == 0 { 2 } else { 1 };
        sum += addend / 32 + addend % 32;
    }
    u8::try_from((32 - sum % 32) % 32).unwrap_or(0)
}

impl RecoveryCode {
    /// A fresh code from the system's random source.
    ///
    /// # Errors
    ///
    /// [`AuthError::Random`] when the system cannot supply random bytes.
    pub fn generate() -> Result<Self, AuthError> {
        let mut bytes = [0u8; 16];
        random(&mut bytes)?;
        Ok(Self(bytes))
    }

    /// The 26 data symbols, most significant first.
    fn data_symbols(&self) -> [u8; DATA_SYMBOLS] {
        let value = u128::from_be_bytes(self.0);
        let mut out = [0u8; DATA_SYMBOLS];
        for (i, s) in out.iter_mut().enumerate() {
            let shift = 5 * (DATA_SYMBOLS - 1 - i);
            *s = u8::try_from((value >> shift) & 31).unwrap_or(0);
        }
        out
    }

    /// The displayed form: 27 symbols in groups of four, joined by `-`.
    #[must_use]
    pub fn display(&self) -> String {
        let mut symbols = self.data_symbols().to_vec();
        symbols.push(check_value(&symbols));
        let mut out = String::with_capacity(RECOVERY_SYMBOLS + RECOVERY_SYMBOLS / GROUP);
        for (i, v) in symbols.iter().enumerate() {
            if i > 0 && i % GROUP == 0 {
                out.push('-');
            }
            out.push(char::from(ALPHABET[usize::from(*v)]));
        }
        out
    }

    /// Reads a code as a person typed it, or `None` when it has the wrong
    /// number of symbols, a symbol outside the alphabet, a first symbol too
    /// large for 128 bits, or a wrong check symbol.
    #[must_use]
    pub fn parse(input: &str) -> Option<Self> {
        if input.chars().count() > MAX_INPUT_CHARS {
            return None;
        }
        let mut symbols = Vec::with_capacity(RECOVERY_SYMBOLS);
        for c in input.chars() {
            if c.is_whitespace() || c == '-' {
                continue;
            }
            symbols.push(symbol_value(c)?);
        }
        let (&check, data) = symbols.split_last()?;
        if data.len() != DATA_SYMBOLS || check_value(data) != check {
            return None;
        }
        // 26 symbols carry 130 bits; the first one may only use 3 of its 5.
        if data.first().is_some_and(|&v| v >= 8) {
            return None;
        }
        let value = data
            .iter()
            .fold(0u128, |acc, &v| (acc << 5) | u128::from(v));
        Some(Self(value.to_be_bytes()))
    }

    /// The stored hash of the code: argon2id (19 MiB, 2 passes, 1 lane)
    /// of its 16 bytes under the fixed salt, 32 bytes. Measured at 13 ms
    /// in a release build on an Apple M2 Ultra (`hash_time` below); CPU
    /// work, so the API runs it off the async threads.
    ///
    /// # Errors
    ///
    /// [`AuthError::Hash`] when argon2 refuses its parameters, which are
    /// constants: only a change of this file can cause it.
    pub fn hash(&self) -> Result<[u8; 32], AuthError> {
        let params = Params::new(MEMORY_KIB, PASSES, LANES, Some(32)).map_err(AuthError::Hash)?;
        let mut out = [0u8; 32];
        Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
            .hash_password_into(&self.0, SALT, &mut out)
            .map_err(AuthError::Hash)?;
        Ok(out)
    }

    #[cfg(test)]
    const fn from_bytes(bytes: [u8; 16]) -> Self {
        Self(bytes)
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn a_code_reads_back_however_it_is_typed() {
        let code = RecoveryCode::generate().unwrap();
        let shown = code.display();
        assert_eq!(shown.len(), 33, "27 symbols and 6 hyphens: {shown}");
        assert_eq!(RecoveryCode::parse(&shown), Some(code.clone()));
        let sloppy = shown.replace('-', " ").to_lowercase();
        assert_eq!(RecoveryCode::parse(&sloppy), Some(code.clone()));
        let squashed: String = shown.chars().filter(|c| *c != '-').collect();
        assert_eq!(RecoveryCode::parse(&squashed), Some(code));
    }

    #[test]
    fn look_alike_letters_read_as_digits() {
        let code = RecoveryCode::from_bytes([0; 16]);
        let shown = code.display();
        assert!(shown.starts_with("0000"));
        let with_letters = shown.replacen('0', "O", 1).replacen('0', "o", 1);
        assert_eq!(RecoveryCode::parse(&with_letters), Some(code));
        let ones = RecoveryCode::from_bytes([0x08; 16]);
        assert!(ones.display().contains('1'));
        assert_eq!(
            RecoveryCode::parse(&ones.display().replace('1', "l")),
            Some(ones.clone())
        );
        assert_eq!(
            RecoveryCode::parse(&ones.display().replace('1', "I")),
            Some(ones)
        );
    }

    #[test]
    fn a_mistyped_symbol_is_caught_by_the_check() {
        let code = RecoveryCode::generate().unwrap();
        let shown: Vec<char> = code.display().chars().collect();
        for i in (0..shown.len()).filter(|i| shown[*i] != '-') {
            for &replacement in ALPHABET {
                let replacement = char::from(replacement);
                if replacement == shown[i] {
                    continue;
                }
                let mut typo = shown.clone();
                typo[i] = replacement;
                let typo: String = typo.into_iter().collect();
                assert_eq!(
                    RecoveryCode::parse(&typo),
                    None,
                    "one wrong symbol must not pass: {typo}"
                );
            }
        }
    }

    #[test]
    fn wrong_lengths_and_symbols_are_refused() {
        let shown = RecoveryCode::generate().unwrap().display();
        assert_eq!(RecoveryCode::parse(&shown[..shown.len() - 1]), None);
        assert_eq!(RecoveryCode::parse(&format!("{shown}0")), None);
        assert_eq!(RecoveryCode::parse(&shown.replacen('-', "U", 1)), None);
        assert_eq!(RecoveryCode::parse(""), None);
        assert_eq!(RecoveryCode::parse(&"0".repeat(500)), None);
        // A first symbol of 8 or more would need 130 bits.
        let mut data = [0u8; DATA_SYMBOLS];
        data[0] = 8;
        let mut symbols = data.to_vec();
        symbols.push(check_value(&data));
        let over: String = symbols
            .iter()
            .map(|v| char::from(ALPHABET[usize::from(*v)]))
            .collect();
        assert_eq!(RecoveryCode::parse(&over), None);
    }

    #[test]
    fn the_hash_finds_the_code_and_only_it() {
        let a = RecoveryCode::from_bytes([7; 16]);
        let b = RecoveryCode::from_bytes([8; 16]);
        let ha = a.hash().unwrap();
        assert_eq!(
            a.hash().unwrap(),
            ha,
            "a fixed salt: the same code, the same hash"
        );
        assert_ne!(b.hash().unwrap(), ha);
        assert_eq!(
            RecoveryCode::parse(&a.display()).unwrap().hash().unwrap(),
            ha,
            "the displayed form hashes as the bytes it stands for"
        );
    }

    #[test]
    fn debug_never_shows_the_secret() {
        let code = RecoveryCode::from_bytes([0xab; 16]);
        assert_eq!(format!("{code:?}"), "RecoveryCode(..)");
    }

    /// Run with `cargo test --release -p lunaway-auth -- --ignored
    /// --nocapture hash_time` to measure what one attempt costs the server.
    #[test]
    #[ignore = "a measurement, meaningful in a release build only"]
    fn hash_time() {
        let code = RecoveryCode::from_bytes([1; 16]);
        let start = std::time::Instant::now();
        let runs = 20;
        for _ in 0..runs {
            code.hash().unwrap();
        }
        println!(
            "argon2id recovery hash: {:?} per code",
            start.elapsed() / runs
        );
    }

    proptest! {
        #[test]
        fn display_and_parse_are_inverse(bytes in proptest::array::uniform16(any::<u8>())) {
            let code = RecoveryCode::from_bytes(bytes);
            prop_assert_eq!(RecoveryCode::parse(&code.display()), Some(code));
        }

        #[test]
        fn parse_never_panics(s in "\\PC{0,120}") {
            let _ = RecoveryCode::parse(&s);
        }
    }
}
