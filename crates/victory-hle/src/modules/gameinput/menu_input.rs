//! Read-only, numbered guest navigation and movement pulses for diagnostic tests.

use std::fs::OpenOptions;
use std::io::Read;
use std::os::windows::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Component, Path, PathBuf, Prefix};
use std::time::{Duration, Instant};

use windows_sys::Win32::Storage::FileSystem::{
    FILE_ATTRIBUTE_REPARSE_POINT, FILE_FLAG_OPEN_REPARSE_POINT,
};

const POLL_PERIOD: Duration = Duration::from_millis(50);
const NAVIGATION_PULSE: Duration = Duration::from_millis(200);
const MOVEMENT_PULSE: Duration = Duration::from_millis(900);
const MOVEMENT_KEYS: [u8; 4] = *b"WASD";
const COMMAND_BYTES: u64 = 64;

pub(super) struct MenuInput {
    path: Option<PathBuf>,
    next_read: Option<Instant>,
    last_sequence: u64,
    active: Option<(Instant, u8)>,
}

impl Default for MenuInput {
    fn default() -> Self {
        let path = std::env::var_os("VICTORY_MENU_INPUT")
            .map(PathBuf::from)
            .filter(|path| {
                path.is_absolute()
                    && path.file_name().is_some_and(|name| name == "command.txt")
                    && matches!(path.components().next(), Some(Component::Prefix(prefix))
                        if matches!(prefix.kind(), Prefix::Disk(_)))
            });
        Self {
            path,
            next_read: None,
            last_sequence: 0,
            active: None,
        }
    }
}

impl MenuInput {
    pub(super) fn poll(&mut self, now: Instant) -> Option<u8> {
        let path = self.path.as_deref()?;
        if let Some((until, key)) = self.active {
            if now < until {
                return Some(key);
            }
            self.active = None;
            // The guest needs to see a release between two pulses of the same key.
            self.next_read = Some(now + POLL_PERIOD);
            return None;
        }
        if self.next_read.is_some_and(|next| now < next) {
            return None;
        }
        self.next_read = Some(now + POLL_PERIOD);
        let (sequence, key) = read_command(path)?;
        if sequence <= self.last_sequence {
            return None;
        }
        self.last_sequence = sequence;
        let duration = if MOVEMENT_KEYS.contains(&key) {
            MOVEMENT_PULSE
        } else {
            NAVIGATION_PULSE
        };
        self.active = Some((now + duration, key));
        tracing::info!(sequence, key, "offline menu input pulse");
        Some(key)
    }
}

fn read_command(path: &Path) -> Option<(u64, u8)> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .open(path)
        .ok()?;
    let info = file.metadata().ok()?;
    if !info.is_file() || info.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
        return None;
    }
    let mut command = String::new();
    let count = file
        .take(COMMAND_BYTES + 1)
        .read_to_string(&mut command)
        .ok()?;
    if count as u64 > COMMAND_BYTES {
        return None;
    }
    let (sequence, key) = command.trim().split_once(':')?;
    let key = key.trim();
    let key = match key.as_bytes() {
        [movement] if MOVEMENT_KEYS.contains(movement) => *movement,
        _ => navigation_key(key)?,
    };
    Some((sequence.trim().parse().ok()?, key))
}

pub(super) fn navigation_key(key: &str) -> Option<u8> {
    Some(match key {
        "Enter" => 0x0D,
        "Esc" => 0x1B,
        "Up" => 0x26,
        "Down" => 0x28,
        "Left" => 0x25,
        "Right" => 0x27,
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_only_fresh_bounded_commands_and_releases_between_pulses() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("command.txt");
        let mut input = MenuInput {
            path: Some(path.clone()),
            next_read: None,
            last_sequence: 0,
            active: None,
        };
        let start = Instant::now();
        let at = |millis| start + Duration::from_millis(millis);
        std::fs::write(&path, "1:Enter\n").unwrap();
        assert_eq!(input.poll(at(0)), Some(0x0D));

        std::fs::write(&path, "2:Enter").unwrap();
        assert_eq!(input.poll(at(199)), Some(0x0D));
        assert_eq!(input.poll(at(200)), None);
        assert_eq!(input.poll(at(249)), None);
        assert_eq!(input.poll(at(250)), Some(0x0D));
        assert_eq!(input.poll(at(450)), None);
        assert_eq!(input.poll(at(500)), None);

        std::fs::write(&path, "3:F").unwrap();
        assert_eq!(input.poll(at(550)), None);
        std::fs::write(&path, format!("3:Esc{}", " ".repeat(64))).unwrap();
        assert_eq!(input.poll(at(600)), None);
        std::fs::write(&path, "3:Esc\r\n").unwrap();
        assert_eq!(input.poll(at(650)), Some(0x1B));
        assert_eq!(input.poll(at(850)), None);

        std::fs::write(&path, "4:W").unwrap();
        assert_eq!(input.poll(at(899)), None);
        assert_eq!(input.poll(at(900)), Some(b'W'));
        assert_eq!(input.poll(at(1799)), Some(b'W'));
        assert_eq!(input.poll(at(1800)), None);
        assert_eq!(input.poll(at(1850)), None);
    }
}
