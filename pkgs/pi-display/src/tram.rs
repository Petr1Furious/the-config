use std::collections::HashSet;
use std::time::{Duration, Instant};

use jiff::civil::DateTime;
use jiff::tz::TimeZone;
use jiff::{Timestamp, Zoned};
use serde::Deserialize;

use crate::error::{Error, Result};

const OPPOSITE_REFRESH: Duration = Duration::from_secs(24 * 3600);

#[derive(Debug, Clone, PartialEq)]
pub struct Departure {
    pub line: String,
    pub direction: String,
    pub time: Zoned,
    pub cancelled: bool,
}

#[derive(Deserialize)]
struct Response {
    data: Data,
}

#[derive(Deserialize)]
struct Data {
    departures: Vec<RawDeparture>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawDeparture {
    name: String,
    direction: String,
    date_time: String,
    rt_date_time: Option<String>,
    cancelled: bool,
}

/// Parses a departures response. Its times are Danish local time without an
/// offset.
pub fn parse(json: &str, tz: &TimeZone) -> Result<Vec<Departure>> {
    let response: Response = serde_json::from_str(json)?;
    response
        .data
        .departures
        .into_iter()
        .map(|d| {
            let local = d.rt_date_time.as_deref().unwrap_or(&d.date_time);
            Ok(Departure {
                line: d.name,
                direction: d.direction,
                time: local.parse::<DateTime>()?.to_zoned(tz.clone())?,
                cancelled: d.cancelled,
            })
        })
        .collect()
}

/// Departures that haven't left yet, soonest first.
pub fn upcoming(departures: &[Departure], now: Timestamp) -> Vec<&Departure> {
    let mut upcoming: Vec<_> = departures
        .iter()
        .filter(|d| d.time.timestamp() >= now)
        .collect();
    upcoming.sort_by_key(|d| d.time.timestamp());
    upcoming
}

/// Destinations served by `departures`.
pub fn directions(departures: &[Departure]) -> HashSet<String> {
    departures.iter().map(|d| d.direction.clone()).collect()
}

/// Drops departures heading to any of `away`.
pub fn without(departures: Vec<Departure>, away: &HashSet<String>) -> Vec<Departure> {
    departures
        .into_iter()
        .filter(|d| !away.contains(&d.direction))
        .collect()
}

fn url(stop: &str) -> String {
    format!("https://apilivemidttrafik.adibuslive.com/api/stops/departures/{stop}")
}

pub struct Client {
    agent: ureq::Agent,
    stops: Vec<String>,
    opposite: String,
    /// Destinations of the opposite direction, learned from `opposite`.
    away: Option<(HashSet<String>, Instant)>,
}

impl Client {
    pub fn new(agent: ureq::Agent, stops: &[String], opposite: &str) -> Self {
        Self {
            agent,
            stops: stops.to_vec(),
            opposite: opposite.to_owned(),
            away: None,
        }
    }

    fn get(&self, stop: &str, tz: &TimeZone) -> Result<Vec<Departure>> {
        let body = self
            .agent
            .get(url(stop))
            .header("Accept", "application/json")
            .call()?
            .body_mut()
            .read_to_string()?;
        parse(&body, tz)
    }

    /// Learns the opposite direction's destinations on first use and once a
    /// day after that; a failed refresh keeps the previous set.
    fn refresh_away(&mut self, tz: &TimeZone) -> Result<&HashSet<String>> {
        if self
            .away
            .as_ref()
            .is_none_or(|(_, at)| at.elapsed() >= OPPOSITE_REFRESH)
        {
            let learned = self.get(&self.opposite, tz).and_then(|deps| {
                let away = directions(&deps);
                if away.is_empty() {
                    Err(Error::NoOppositeDepartures(self.opposite.clone()))
                } else {
                    Ok(away)
                }
            });
            match (learned, &mut self.away) {
                (Ok(away), slot) => *slot = Some((away, Instant::now())),
                (Err(_), Some((_, at))) => *at = Instant::now(),
                (Err(e), None) => return Err(e),
            }
        }
        Ok(&self.away.as_ref().expect("set above").0)
    }

    /// Departures from all stops towards the configured direction, or an error
    /// if any stop fails: showing only some platforms would silently hide trams.
    pub fn fetch(&mut self, tz: &TimeZone) -> Result<Vec<Departure>> {
        let away = self.refresh_away(tz)?.clone();
        let mut all = Vec::new();
        for stop in &self.stops {
            all.extend(self.get(stop, tz)?);
        }
        Ok(without(all, &away))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tz() -> TimeZone {
        TimeZone::get("Europe/Copenhagen").unwrap()
    }

    fn at(local: &str) -> Timestamp {
        local
            .parse::<DateTime>()
            .unwrap()
            .to_zoned(tz())
            .unwrap()
            .timestamp()
    }

    #[test]
    fn parses_a_real_response() {
        let json = include_str!("../tests/fixtures/departures.json");
        let deps = parse(json, &tz()).unwrap();
        assert_eq!(deps.len(), 8);
        assert_eq!(deps[0].line, "L2");
        assert_eq!(deps[0].direction, "Aarhus H");
        assert_eq!(deps[6].direction, "Mårslet");
        assert_eq!(deps[0].time.datetime().to_string(), "2026-09-28T00:09:00");
        assert!(!deps[0].cancelled);
    }

    #[test]
    fn local_times_follow_daylight_saving() {
        let summer = at("2026-09-28T12:00:00");
        let winter = at("2026-12-28T12:00:00");
        assert_eq!(summer.to_string(), "2026-09-28T10:00:00Z");
        assert_eq!(winter.to_string(), "2026-12-28T11:00:00Z");
    }

    #[test]
    fn real_time_wins_over_schedule() {
        let json = r#"{"data":{"departures":[{"name":"L2","direction":"Aarhus H",
            "dateTime":"2026-09-28T08:00:00","rtDateTime":"2026-09-28T08:03:00",
            "cancelled":false}]}}"#;
        let deps = parse(json, &tz()).unwrap();
        assert_eq!(deps[0].time.datetime().to_string(), "2026-09-28T08:03:00");
    }

    #[test]
    fn platforms_interleave() {
        let mut all = parse(include_str!("../tests/fixtures/platform-102.json"), &tz()).unwrap();
        all.extend(parse(include_str!("../tests/fixtures/platform-103.json"), &tz()).unwrap());
        let next: Vec<_> = upcoming(&all, at("2026-09-28T08:05:00"))
            .iter()
            .take(4)
            .map(|d| format!("{} {}", d.time.strftime("%H:%M"), d.direction))
            .collect();
        assert_eq!(
            next,
            [
                "08:09 Mårslet",
                "08:16 Aarhus H",
                "08:24 Odder",
                "08:31 Aarhus H"
            ]
        );
    }

    #[test]
    fn opposite_direction_is_hidden() {
        let away =
            directions(&parse(include_str!("../tests/fixtures/platform-101.json"), &tz()).unwrap());
        let mixed = parse(
            include_str!("../tests/fixtures/platform-103-night.json"),
            &tz(),
        )
        .unwrap();
        let kept: Vec<_> = without(mixed, &away)
            .iter()
            .map(|d| format!("{} {}", d.time.strftime("%H:%M"), d.direction))
            .collect();
        assert_eq!(kept, ["23:54 Aarhus H", "00:09 Aarhus H", "00:24 Odder"]);
    }

    #[test]
    fn upcoming_skips_departed_and_sorts() {
        let json = include_str!("../tests/fixtures/departures.json");
        let deps = parse(json, &tz()).unwrap();
        let next = upcoming(&deps, at("2026-09-28T01:00:00"));
        assert_eq!(next.len(), 4);
        assert_eq!(next[0].time.datetime().to_string(), "2026-09-28T01:09:00");
        assert_eq!(next[1].time.datetime().to_string(), "2026-09-28T05:24:00");
    }
}
