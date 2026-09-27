use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::error::Result;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Air {
    pub iaq: Option<f64>,
    pub temperature: Option<f64>,
    pub humidity: Option<f64>,
}

/// Reads the few unlabelled gauges the display needs from the exporter's text
/// exposition. `bme688_iaq` is absent while the exporter withholds it.
pub fn parse(text: &str) -> Air {
    let mut air = Air::default();
    for line in text.lines() {
        let Some((name, value)) = line.split_once(' ') else {
            continue;
        };
        let Ok(value) = value.trim().parse::<f64>() else {
            continue;
        };
        match name {
            "bme688_iaq" => air.iaq = Some(value),
            "bme688_temperature_celsius" => air.temperature = Some(value),
            "bme688_humidity_ratio" => air.humidity = Some(value * 100.0),
            _ => {}
        }
    }
    air
}

pub fn fetch(agent: &ureq::Agent, url: &str) -> Result<Air> {
    let text = agent.get(url).call()?.body_mut().read_to_string()?;
    Ok(parse(&text))
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Direction {
    Up,
    Down,
}

const TREND_WINDOW: Duration = Duration::from_secs(15 * 60);
const TREND_MIN_SPAN: Duration = Duration::from_secs(10 * 60);
const TREND_THRESHOLD: f64 = 15.0;

/// IAQ change over roughly the last quarter hour.
#[derive(Default)]
pub struct Trend {
    history: VecDeque<(Instant, f64)>,
}

impl Trend {
    pub fn push(&mut self, at: Instant, iaq: f64) {
        self.history.push_back((at, iaq));
        while let Some(&(t, _)) = self.history.front() {
            if at.duration_since(t) <= TREND_WINDOW {
                break;
            }
            self.history.pop_front();
        }
    }

    pub fn direction(&self) -> Option<Direction> {
        let (&(first_at, first), &(last_at, last)) = (self.history.front()?, self.history.back()?);
        if last_at.duration_since(first_at) < TREND_MIN_SPAN {
            return None;
        }
        let change = last - first;
        if change >= TREND_THRESHOLD {
            Some(Direction::Up)
        } else if change <= -TREND_THRESHOLD {
            Some(Direction::Down)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const METRICS: &str = "\
# HELP bme688_temperature_celsius Compensated temperature.
# TYPE bme688_temperature_celsius gauge
bme688_temperature_celsius 24.25
bme688_raw_temperature_celsius 24.36
bme688_humidity_ratio 0.4561
bme688_iaq 152.4
bme688_iaq_accuracy 3.0
bme688_errors_total{kind=\"io\"} 0
# EOF
";

    #[test]
    fn parses_the_display_gauges() {
        let air = parse(METRICS);
        assert_eq!(air.temperature, Some(24.25));
        assert_eq!(air.iaq, Some(152.4));
        assert!((air.humidity.unwrap() - 45.61).abs() < 1e-9);
    }

    #[test]
    fn iaq_is_absent_during_the_startup_hold() {
        let air = parse(&METRICS.replace("bme688_iaq 152.4\n", ""));
        assert_eq!(air.iaq, None);
        assert_eq!(air.temperature, Some(24.25));
    }

    #[test]
    fn trend_needs_ten_minutes_of_history() {
        let t0 = Instant::now();
        let mut trend = Trend::default();
        trend.push(t0, 100.0);
        trend.push(t0 + Duration::from_secs(9 * 60), 150.0);
        assert_eq!(trend.direction(), None);
        trend.push(t0 + Duration::from_secs(11 * 60), 150.0);
        assert_eq!(trend.direction(), Some(Direction::Up));
    }

    #[test]
    fn trend_ignores_small_changes_and_old_samples() {
        let t0 = Instant::now();
        let mut trend = Trend::default();
        trend.push(t0, 300.0);
        trend.push(t0 + Duration::from_secs(5 * 60), 110.0);
        trend.push(t0 + Duration::from_secs(20 * 60), 100.0);
        assert_eq!(trend.direction(), None);
        let mut falling = Trend::default();
        falling.push(t0, 200.0);
        falling.push(t0 + Duration::from_secs(12 * 60), 150.0);
        assert_eq!(falling.direction(), Some(Direction::Down));
    }
}
