mod air;
mod error;
mod icons;
mod radar;
mod screen;
mod tram;

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use clap::Parser;
use embedded_graphics::prelude::Point;
use jiff::Zoned;
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
const TICK: Duration = Duration::from_millis(100);

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
    /// ld2410-stream address; the display is lit only while somebody is near.
    #[arg(long, default_value = "100.67.147.81:2410")]
    radar: String,
    /// Furthest distance that counts as near, in cm.
    #[arg(long, default_value_t = 100)]
    near_cm: u16,
    /// Seconds the display stays lit after the last near reading.
    #[arg(long, default_value_t = 30)]
    hold_secs: u64,
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

    let presence = Arc::new(Mutex::new(radar::Presence::new(
        args.near_cm,
        Duration::from_secs(args.hold_secs),
    )));
    radar::spawn(args.radar.clone(), Arc::clone(&presence));
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
        "display at {:#04x} on {}, stops {} (not towards {}), lit within {} cm per {}",
        args.address,
        args.bus.display(),
        args.stops.join(" "),
        args.opposite_stop,
        args.near_cm,
        args.radar
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
    let mut radar_error = None;
    let mut on = true;

    while !stop.load(Ordering::Relaxed) {
        let now = Zoned::now().with_time_zone(tz.clone());
        let (near, blind) = {
            let presence = presence.lock().unwrap();
            (
                presence.near(Instant::now()),
                presence.blind(Instant::now()),
            )
        };
        report(
            "radar",
            &mut radar_error,
            if blind {
                Err(format!("no readings from {}", args.radar))
            } else {
                Ok(())
            },
        );
        // Without the radar the display stays lit rather than dark for good.
        let lit = near || blind;
        if lit != on {
            display.set_display_on(lit).map_err(display_err)?;
            on = lit;
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

        if on && (changed || last_draw.is_none_or(|t| t.elapsed() >= REDRAW_INTERVAL)) {
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
        thread::sleep(TICK);
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
