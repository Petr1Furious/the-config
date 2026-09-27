use std::fs::{self, File};
use std::io::{self, Write};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

const FORMAT: u32 = 1;

pub const MIN_RESTORE_ACCURACY: u8 = 2;

pub enum Loaded {
    Missing,
    /// Below `MIN_RESTORE_ACCURACY`; the file will be replaced by the first save.
    TooWeak(u8),
    Usable {
        blob: Vec<u8>,
        accuracy: u8,
    },
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Identity {
    pub bsec_version: String,
    pub config: String,
    pub config_hash: String,
    pub profile: String,
}

#[derive(Serialize, Deserialize)]
struct StateFile {
    format: u32,
    #[serde(flatten)]
    identity: Identity,
    iaq_accuracy: u8,
    saved_at: u64,
    state: String,
}

pub struct StateStore {
    dir: PathBuf,
    path: PathBuf,
    identity: Identity,
    interval: Duration,
    max_age: Duration,
    /// Accuracy and time of the state on disk, if it is one worth protecting:
    /// restored at startup or saved since.
    saved: Option<(u8, u64)>,
    last_attempt: Instant,
}

impl StateStore {
    pub fn new(dir: PathBuf, identity: Identity, interval: Duration, max_age: Duration) -> Self {
        Self {
            path: dir.join(format!("{}.json", identity.profile)),
            dir,
            identity,
            interval,
            max_age,
            saved: None,
            last_attempt: Instant::now(),
        }
    }

    pub fn path(&self) -> &PathBuf {
        &self.path
    }

    pub fn load(&mut self) -> io::Result<Loaded> {
        let text = match fs::read_to_string(&self.path) {
            Ok(t) => t,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Loaded::Missing),
            Err(e) => return Err(e),
        };
        let file: StateFile = serde_json::from_str(&text).map_err(io::Error::other)?;
        if file.format != FORMAT || file.identity != self.identity {
            let aside = self
                .path
                .with_extension(format!("rejected-{}.json", unix_now()));
            fs::rename(&self.path, &aside)?;
            return Err(io::Error::other(format!(
                "saved state was made by a different BSEC version or config; moved it to {}",
                aside.display()
            )));
        }
        if file.iaq_accuracy < MIN_RESTORE_ACCURACY {
            return Ok(Loaded::TooWeak(file.iaq_accuracy));
        }
        let blob = hex_decode(&file.state)
            .ok_or_else(|| io::Error::other("saved state is not valid hex"))?;
        self.saved = Some((file.iaq_accuracy, file.saved_at));
        Ok(Loaded::Usable {
            blob,
            accuracy: file.iaq_accuracy,
        })
    }

    /// A state is never replaced by a less calibrated one unless it's older than
    /// `max_age`. The interval restarts only on a due save, so a recovered
    /// accuracy is saved right away.
    pub fn claim_save(&mut self, accuracy: u8, settled: bool, force: bool) -> bool {
        if !settled || (!force && self.last_attempt.elapsed() < self.interval) {
            return false;
        }
        let due = match self.saved {
            None => true,
            Some((saved_acc, saved_at)) => {
                accuracy >= saved_acc
                    || unix_now().saturating_sub(saved_at) >= self.max_age.as_secs()
            }
        };
        if due {
            self.last_attempt = Instant::now();
        }
        due
    }

    pub fn save(&mut self, blob: &[u8], accuracy: u8) -> io::Result<()> {
        let now = unix_now();
        let file = StateFile {
            format: FORMAT,
            identity: self.identity.clone(),
            iaq_accuracy: accuracy,
            saved_at: now,
            state: hex_encode(blob),
        };
        let json = serde_json::to_string_pretty(&file).map_err(io::Error::other)?;
        fs::create_dir_all(&self.dir)?;
        let tmp = self.path.with_extension("json.tmp");
        let mut f = File::create(&tmp)?;
        f.write_all(json.as_bytes())?;
        // Without both syncs a power cut can leave the renamed file empty, or
        // the rename itself undone.
        f.sync_all()?;
        fs::rename(&tmp, &self.path)?;
        File::open(&self.dir)?.sync_all()?;
        self.saved = Some((accuracy, now));
        Ok(())
    }
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

pub fn fingerprint(data: &[u8]) -> String {
    let hash = data.iter().fold(0xcbf29ce484222325u64, |h, &b| {
        (h ^ u64::from(b)).wrapping_mul(0x100000001b3)
    });
    format!("{hash:016x}")
}

fn hex_encode(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU32, Ordering};

    use super::*;

    fn identity() -> Identity {
        Identity {
            bsec_version: "3.3.0.1".into(),
            config: "test_config".into(),
            config_hash: "0123456789abcdef".into(),
            profile: "indoor".into(),
        }
    }

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            static N: AtomicU32 = AtomicU32::new(0);
            Self(std::env::temp_dir().join(format!(
                "bme688-state-test-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::Relaxed)
            )))
        }

        fn state_dir(&self) -> PathBuf {
            self.0.join("state")
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn store(dir: &TempDir, interval_secs: u64) -> StateStore {
        StateStore::new(
            dir.state_dir(),
            identity(),
            Duration::from_secs(interval_secs),
            Duration::from_secs(3600),
        )
    }

    fn write_state(dir: &TempDir, accuracy: u8, saved_at: u64, identity: Identity) {
        let file = StateFile {
            format: FORMAT,
            identity,
            iaq_accuracy: accuracy,
            saved_at,
            state: "0a0b".into(),
        };
        fs::create_dir_all(dir.state_dir()).unwrap();
        fs::write(
            dir.state_dir().join("indoor.json"),
            serde_json::to_string(&file).unwrap(),
        )
        .unwrap();
    }

    #[test]
    fn missing_state() {
        let dir = TempDir::new();
        assert!(matches!(store(&dir, 0).load().unwrap(), Loaded::Missing));
    }

    #[test]
    fn save_then_load_round_trips() {
        let dir = TempDir::new();
        store(&dir, 0).save(&[0x01, 0x02, 0xff], 3).unwrap();
        match store(&dir, 0).load().unwrap() {
            Loaded::Usable { blob, accuracy } => {
                assert_eq!(blob, [0x01, 0x02, 0xff]);
                assert_eq!(accuracy, 3);
            }
            _ => panic!("expected a usable state"),
        }
        assert!(!dir.state_dir().join("indoor.json.tmp").exists());
    }

    #[test]
    fn weak_state_is_not_restored_and_may_be_replaced() {
        let dir = TempDir::new();
        write_state(&dir, 1, unix_now(), identity());
        let mut s = store(&dir, 0);
        assert!(matches!(s.load().unwrap(), Loaded::TooWeak(1)));
        assert!(s.claim_save(0, true, false));
    }

    #[test]
    fn mismatched_state_is_moved_aside() {
        let dir = TempDir::new();
        let mut other = identity();
        other.config_hash = "ffffffffffffffff".into();
        write_state(&dir, 3, unix_now(), other);
        assert!(store(&dir, 0).load().is_err());
        let names: Vec<_> = fs::read_dir(dir.state_dir())
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        assert_eq!(names.len(), 1);
        assert!(names[0].starts_with("indoor.rejected-"), "{names:?}");
    }

    #[test]
    fn nothing_is_saved_before_readings_settle() {
        let dir = TempDir::new();
        assert!(!store(&dir, 0).claim_save(3, false, true));
    }

    #[test]
    fn interval_limits_saves_unless_forced() {
        let dir = TempDir::new();
        let mut s = store(&dir, 3600);
        assert!(!s.claim_save(3, true, false));
        assert!(s.claim_save(3, true, true));
    }

    #[test]
    fn restored_state_is_not_replaced_by_a_weaker_one() {
        let dir = TempDir::new();
        write_state(&dir, 3, unix_now(), identity());
        let mut s = store(&dir, 0);
        assert!(matches!(s.load().unwrap(), Loaded::Usable { .. }));
        assert!(!s.claim_save(2, true, true));
        assert!(s.claim_save(3, true, false));
    }

    #[test]
    fn stale_state_may_be_replaced_by_a_weaker_one() {
        let dir = TempDir::new();
        write_state(&dir, 3, unix_now() - 7200, identity());
        let mut s = store(&dir, 0);
        assert!(matches!(s.load().unwrap(), Loaded::Usable { .. }));
        assert!(s.claim_save(1, true, false));
    }

    #[test]
    fn blocked_save_does_not_restart_the_interval() {
        let dir = TempDir::new();
        write_state(&dir, 3, unix_now(), identity());
        let mut s = store(&dir, 3600);
        s.load().unwrap();
        s.last_attempt = Instant::now()
            .checked_sub(Duration::from_secs(7200))
            .unwrap();
        assert!(!s.claim_save(2, true, false));
        assert!(s.claim_save(3, true, false));
        assert!(!s.claim_save(3, true, false));
    }

    #[test]
    fn fingerprint_is_fnv1a() {
        assert_eq!(fingerprint(b""), "cbf29ce484222325");
        assert_eq!(fingerprint(b"a"), "af63dc4c8601ec8c");
    }

    #[test]
    fn hex_round_trips() {
        let data = [0x00, 0x7f, 0x80, 0xff];
        assert_eq!(hex_decode(&hex_encode(&data)).unwrap(), data);
        assert!(hex_decode("abc").is_none());
        assert!(hex_decode("zz").is_none());
    }
}
