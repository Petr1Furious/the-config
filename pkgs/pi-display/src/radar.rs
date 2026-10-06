use std::io::{BufRead, BufReader};
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde::Deserialize;

const RECONNECT: Duration = Duration::from_secs(2);
const READ_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    None,
    Moving,
    Stationary,
    Both,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Target {
    pub cm: u16,
}

/// One line of the ld2410-stream feed.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Reading {
    pub state: State,
    pub moving: Target,
    pub stationary: Target,
}

impl Reading {
    fn moving_within(&self, cm: u16) -> bool {
        matches!(self.state, State::Moving | State::Both) && self.moving.cm <= cm
    }

    fn still_within(&self, cm: u16) -> bool {
        matches!(self.state, State::Stationary | State::Both) && self.stationary.cm <= cm
    }
}

/// Decides whether somebody is at the display: movement within `near_cm`
/// wakes it, and any target within `near_cm` then keeps it awake. A still
/// target alone never wakes it, so furniture in range can't hold it on.
#[derive(Debug)]
pub struct Presence {
    near_cm: u16,
    hold: Duration,
    last_near: Option<Instant>,
    last_reading: Option<Instant>,
}

impl Presence {
    pub fn new(near_cm: u16, hold: Duration) -> Self {
        Self {
            near_cm,
            hold,
            last_near: None,
            last_reading: None,
        }
    }

    pub fn update(&mut self, reading: &Reading, now: Instant) {
        self.last_reading = Some(now);
        if reading.moving_within(self.near_cm)
            || (self.near(now) && reading.still_within(self.near_cm))
        {
            self.last_near = Some(now);
        }
    }

    pub fn near(&self, now: Instant) -> bool {
        self.last_near
            .is_some_and(|at| now.duration_since(at) < self.hold)
    }

    /// Whether readings have stopped arriving.
    pub fn blind(&self, now: Instant) -> bool {
        self.last_reading
            .is_none_or(|at| now.duration_since(at) >= READ_TIMEOUT)
    }
}

fn follow(address: &str, presence: &Mutex<Presence>) -> std::io::Result<()> {
    let stream = TcpStream::connect(address)?;
    stream.set_read_timeout(Some(READ_TIMEOUT))?;
    for line in BufReader::new(stream).lines() {
        if let Ok(reading) = serde_json::from_str::<Reading>(&line?) {
            presence.lock().unwrap().update(&reading, Instant::now());
        }
    }
    Ok(())
}

/// Keeps `presence` fed from the stream at `address`, reconnecting forever.
pub fn spawn(address: String, presence: Arc<Mutex<Presence>>) {
    thread::spawn(move || {
        loop {
            let _ = follow(&address, &presence);
            thread::sleep(RECONNECT);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reading(state: State, moving: u16, stationary: u16) -> Reading {
        Reading {
            state,
            moving: Target { cm: moving },
            stationary: Target { cm: stationary },
        }
    }

    fn presence() -> Presence {
        Presence::new(100, Duration::from_secs(30))
    }

    #[test]
    fn parses_a_stream_line() {
        let line = r#"{"t":1791238208.2,"state":"both","moving":{"cm":39,"energy":67},
            "stationary":{"cm":30,"energy":100},"detection_cm":40,"light":0,"out":true}"#;
        let r: Reading = serde_json::from_str(line).unwrap();
        assert_eq!(r.state, State::Both);
        assert_eq!((r.moving.cm, r.stationary.cm), (39, 30));
    }

    #[test]
    fn movement_nearby_wakes() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Moving, 100, 0), t);
        assert!(p.near(t));
    }

    #[test]
    fn movement_further_away_does_not_wake() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Both, 101, 250), t);
        assert!(!p.near(t));
    }

    #[test]
    fn a_still_target_alone_does_not_wake() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Stationary, 0, 40), t);
        assert!(!p.near(t));
    }

    #[test]
    fn the_distance_of_an_absent_target_is_ignored() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Stationary, 40, 300), t);
        p.update(&reading(State::None, 40, 40), t);
        assert!(!p.near(t));
    }

    #[test]
    fn a_still_target_keeps_it_awake() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Moving, 60, 0), t);
        let later = t + Duration::from_secs(29);
        p.update(&reading(State::Stationary, 0, 60), later);
        assert!(p.near(later + Duration::from_secs(29)));
    }

    #[test]
    fn sleeps_after_the_hold_time() {
        let (mut p, t) = (presence(), Instant::now());
        p.update(&reading(State::Moving, 60, 0), t);
        let later = t + Duration::from_secs(30);
        assert!(!p.near(later));
        p.update(&reading(State::Stationary, 0, 60), later);
        assert!(!p.near(later));
    }

    #[test]
    fn blind_without_recent_readings() {
        let (mut p, t) = (presence(), Instant::now());
        assert!(p.blind(t));
        p.update(&reading(State::None, 0, 0), t);
        assert!(!p.blind(t + Duration::from_secs(4)));
        assert!(p.blind(t + Duration::from_secs(5)));
    }
}
