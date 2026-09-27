use jiff::civil::DateTime;
use jiff::tz::TimeZone;
use jiff::{Timestamp, Zoned};
use serde::Deserialize;

use crate::error::Result;

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

pub struct Client {
    agent: ureq::Agent,
    url: String,
}

impl Client {
    pub fn new(agent: ureq::Agent, stop: &str) -> Self {
        Self {
            agent,
            url: format!("https://apilivemidttrafik.adibuslive.com/api/stops/departures/{stop}"),
        }
    }

    pub fn fetch(&self, tz: &TimeZone) -> Result<Vec<Departure>> {
        let body = self
            .agent
            .get(&self.url)
            .header("Accept", "application/json")
            .call()?
            .body_mut()
            .read_to_string()?;
        parse(&body, tz)
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
    fn upcoming_skips_departed_and_sorts() {
        let json = include_str!("../tests/fixtures/departures.json");
        let deps = parse(json, &tz()).unwrap();
        let next = upcoming(&deps, at("2026-09-28T01:00:00"));
        assert_eq!(next.len(), 4);
        assert_eq!(next[0].time.datetime().to_string(), "2026-09-28T01:09:00");
        assert_eq!(next[1].time.datetime().to_string(), "2026-09-28T05:24:00");
    }
}
