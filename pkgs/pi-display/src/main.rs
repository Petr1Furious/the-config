mod air;
mod error;
mod icons;
mod screen;
mod tram;

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use clap::Parser;
use embedded_graphics::prelude::Point;
use jiff::Zoned;
use jiff::civil::Time;
use jiff::tz::TimeZone;
use linux_embedded_hal::I2cdev;
use ssd1306::prelude::*;
use ssd1306::{I2CDisplayInterface, Ssd1306};

use crate::air::Trend;
use crate::error::{Error, Result};

const USER_AGENT: &str = "pi-display (personal departure board)";
const AIR_INTERVAL: Duration = Duration::from_secs(10);
const AIR_MAX_AGE: Duration = Duration::from_secs(60);
const TRAM_INTERVAL: Duration = Duration::from_secs(60);
const TRAM_MAX_BACKOFF: Duration = Duration::from_secs(600);
const TRAMS_MAX_AGE: Duration = Duration::from_secs(300);
const REDRAW_INTERVAL: Duration = Duration::from_secs(10);

/// Next trams and air quality on an SSD1306 OLED.
#[derive(Parser)]
struct Args {
    /// Midttrafik stop id; repeat for several platforms.
    #[arg(long = "stop", default_values = ["860431102", "860431103"])]
    stops: Vec<String>,
    /// Platform serving the opposite direction; its destinations are hidden.
    #[arg(long, default_value = "860431101")]
    opposite_stop: String,
    /// bme688-exporter metrics URL.
    #[arg(long, default_value = "http://100.67.147.81:9688/metrics")]
    metrics_url: String,
    /// Local time range with the display off, HH:MM-HH:MM.
    #[arg(long, default_value = "01:00-07:00")]
    off_hours: String,
    /// I2C bus device.
    #[arg(long, default_value = "/dev/i2c-1")]
    bus: PathBuf,
    /// I2C address.
    #[arg(long, default_value = "0x3c", value_parser = parse_address)]
    address: u8,
}

fn parse_address(s: &str) -> std::result::Result<u8, String> {
    u8::from_str_radix(s.trim_start_matches("0x"), 16).map_err(|e| e.to_string())
}

fn parse_off_hours(s: &str) -> Result<(Time, Time)> {
    let err = || Error::OffHours(s.into());
    let (start, end) = s.split_once('-').ok_or_else(err)?;
    let time = |t: &str| format!("{t}:00").parse::<Time>().map_err(|_| err());
    Ok((time(start)?, time(end)?))
}

fn is_off(now: Time, (start, end): (Time, Time)) -> bool {
    if start <= end {
        start <= now && now < end
    } else {
        now >= start || now < end
    }
}

/// Moves the picture by up to 2 px every 5 minutes against burn-in.
fn burn_in_offset(now: &Zoned) -> Point {
    let step = now.timestamp().as_second().div_euclid(300) % 9;
    Point::new((step % 3) as i32, (step / 3) as i32)
}

fn display_err(e: impl std::fmt::Debug) -> Error {
    Error::Display(format!("{e:?}"))
}

/// Logs a source's error only when it changes, not on every retry.
fn report(source: &str, last: &mut Option<String>, result: std::result::Result<(), String>) {
    match result {
        Ok(()) if last.take().is_some() => eprintln!("{source}: recovered"),
        Err(e) if last.as_ref() != Some(&e) => {
            eprintln!("{source}: {e}");
            *last = Some(e);
        }
        _ => {}
    }
}

fn run(args: Args) -> Result<()> {
    let stop = Arc::new(AtomicBool::new(false));
    for sig in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(sig, Arc::clone(&stop))?;
    }

    let off_hours = parse_off_hours(&args.off_hours)?;
    let tz = TimeZone::get("Europe/Copenhagen")?;
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(10)))
        .user_agent(USER_AGENT)
        .build()
        .into();
    let mut trams = tram::Client::new(agent.clone(), &args.stops, &args.opposite_stop);

    let i2c = I2cdev::new(&args.bus).map_err(display_err)?;
    let interface = I2CDisplayInterface::new_custom_address(i2c, args.address);
    let mut display = Ssd1306::new(interface, DisplaySize128x64, DisplayRotation::Rotate0)
        .into_buffered_graphics_mode();
    display.init().map_err(display_err)?;
    display
        .set_brightness(Brightness::DIM)
        .map_err(display_err)?;
    eprintln!(
        "display at {:#04x} on {}, stops {} (not towards {}), off {}",
        args.address,
        args.bus.display(),
        args.stops.join(" "),
        args.opposite_stop,
        args.off_hours
    );

    let mut departures: Option<(Vec<tram::Departure>, Instant)> = None;
    let mut tram_backoff = TRAM_INTERVAL;
    let mut next_tram = Instant::now();
    let mut tram_error = None;
    let mut air: Option<(air::Air, Instant)> = None;
    let mut next_air = Instant::now();
    let mut air_error = None;
    let mut trend = Trend::default();
    let mut last_draw: Option<Instant> = None;
    let mut on = true;

    while !stop.load(Ordering::Relaxed) {
        let now = Zoned::now().with_time_zone(tz.clone());
        if is_off(now.time(), off_hours) {
            if on {
                display.set_display_on(false).map_err(display_err)?;
                on = false;
            }
            thread::sleep(Duration::from_secs(1));
            continue;
        }
        if !on {
            display.set_display_on(true).map_err(display_err)?;
            on = true;
            last_draw = None;
        }

        let mut changed = false;
        if Instant::now() >= next_air {
            next_air = Instant::now() + AIR_INTERVAL;
            let result = air::fetch(&agent, &args.metrics_url);
            if let Ok(a) = &result {
                if let Some(iaq) = a.iaq {
                    trend.push(Instant::now(), iaq);
                }
                air = Some((a.clone(), Instant::now()));
                changed = true;
            }
            report(
                "air",
                &mut air_error,
                result.map(drop).map_err(|e| e.to_string()),
            );
        }
        if Instant::now() >= next_tram {
            let result = trams.fetch(&tz);
            match &result {
                Ok(d) => {
                    departures = Some((d.clone(), Instant::now()));
                    tram_backoff = TRAM_INTERVAL;
                    changed = true;
                }
                Err(_) => tram_backoff = (tram_backoff * 2).min(TRAM_MAX_BACKOFF),
            }
            next_tram = Instant::now() + tram_backoff;
            report(
                "trams",
                &mut tram_error,
                result.map(drop).map_err(|e| e.to_string()),
            );
        }

        if changed || last_draw.is_none_or(|t| t.elapsed() >= REDRAW_INTERVAL) {
            let fresh_air = air.as_ref().filter(|(_, at)| at.elapsed() < AIR_MAX_AGE);
            let inputs = screen::Inputs {
                departures: departures.as_ref().map(|(d, _)| d.as_slice()),
                trams_stale: departures
                    .as_ref()
                    .is_none_or(|(_, at)| at.elapsed() >= TRAMS_MAX_AGE),
                air: fresh_air.map(|(a, _)| a),
                trend: trend.direction(),
            };
            let layout = screen::layout(&inputs, &now);
            display.clear_buffer();
            screen::draw(&mut display, &layout, burn_in_offset(&now)).map_err(display_err)?;
            display.flush().map_err(display_err)?;
            last_draw = Some(Instant::now());
        }
        thread::sleep(Duration::from_secs(1));
    }

    display.clear_buffer();
    display.flush().map_err(display_err)?;
    display.set_display_on(false).map_err(display_err)?;
    Ok(())
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(s: &str) -> Time {
        format!("{s}:00").parse().unwrap()
    }

    #[test]
    fn off_hours_within_a_day_and_across_midnight() {
        let night = parse_off_hours("00:00-07:00").unwrap();
        assert!(is_off(t("00:00"), night));
        assert!(is_off(t("06:59"), night));
        assert!(!is_off(t("07:00"), night));
        assert!(!is_off(t("23:59"), night));

        let wrap = parse_off_hours("23:30-06:00").unwrap();
        assert!(is_off(t("23:45"), wrap));
        assert!(is_off(t("05:00"), wrap));
        assert!(!is_off(t("12:00"), wrap));
    }

    #[test]
    fn off_hours_rejects_garbage() {
        assert!(parse_off_hours("7-9").is_err());
        assert!(parse_off_hours("07:00").is_err());
    }
}
