mod bsec;
mod error;
mod ffi;
mod i2c;
mod metrics;
mod sensor;
mod state;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use clap::Parser;
use prometheus_client::registry::Registry;

use crate::bsec::Bsec;
use crate::error::Result;
use crate::metrics::{Info, Snapshot};
use crate::sensor::Bme68x;
use crate::state::{Identity, Loaded, MIN_RESTORE_ACCURACY, StateStore};

const CONFIG: &[u8] = include_bytes!(env!("BSEC_CONFIG"));
const CONFIG_NAME: &str = env!("BSEC_CONFIG_NAME");
const SAMPLE_RATE: f32 = ffi::BSEC_SAMPLE_RATE_LP as f32;
const MAX_FAILURES: u32 = 10;

/// Prometheus exporter for a BME688 driven by Bosch BSEC.
#[derive(Parser)]
struct Args {
    /// I2C bus device.
    #[arg(long, default_value = "/dev/i2c-1")]
    bus: PathBuf,
    /// I2C address.
    #[arg(long, default_value = "0x76", value_parser = parse_address)]
    address: u8,
    /// Address to serve /metrics on.
    #[arg(long, default_value = "127.0.0.1:9688")]
    listen: SocketAddr,
    /// Calibration profile; each keeps its own saved BSEC state.
    #[arg(long, default_value = "indoor")]
    profile: String,
    /// Directory for saved BSEC state [default: $STATE_DIRECTORY, else
    /// $XDG_STATE_HOME/bme688-exporter]
    #[arg(long)]
    state_dir: Option<PathBuf>,
    /// Seconds between state saves.
    #[arg(long, default_value_t = 300)]
    state_interval: u64,
    /// Seconds after which a saved state may be replaced by a less calibrated one.
    #[arg(long, default_value_t = 86400)]
    state_max_age: u64,
    /// Extra heat reaching the sensor, in °C.
    #[arg(long, default_value_t = 0.0)]
    heat_source: f32,
}

fn parse_address(s: &str) -> std::result::Result<u8, String> {
    let s = s.trim_start_matches("0x");
    u8::from_str_radix(s, 16).map_err(|e| e.to_string())
}

fn default_state_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("STATE_DIRECTORY") {
        return PathBuf::from(dir);
    }
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    base.join("bme688-exporter")
}

fn monotonic_ns() -> i64 {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) };
    ts.tv_sec * 1_000_000_000 + ts.tv_nsec
}

fn unix_now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |d| d.as_secs_f64())
}

/// Bosch's .config files start with a little-endian u32 length of the blob.
fn config_blob() -> &'static [u8] {
    let (len, blob) = CONFIG.split_at(4);
    assert_eq!(
        u32::from_le_bytes(len.try_into().unwrap()) as usize,
        blob.len(),
        "embedded BSEC config has an inconsistent length header"
    );
    blob
}

struct Exporter {
    sensor: Bme68x,
    bsec: Bsec,
    store: StateStore,
    snapshot: Arc<Mutex<Snapshot>>,
    heat_source: f32,
    next_call: i64,
}

impl Exporter {
    fn cycle(&mut self) -> Result<()> {
        let now = monotonic_ns();
        let (settings, status) = self.bsec.sensor_control(now)?;
        self.next_call = settings.next_call;
        self.note_warning(status);

        if settings.trigger_measurement != 1 || settings.op_mode != ffi::BME68X_FORCED_MODE {
            return Ok(());
        }
        let duration = self.sensor.trigger_forced(&settings)?;
        thread::sleep(duration);

        let Some(data) = self.sensor.read()? else {
            return Ok(());
        };
        // As in Bosch's integration: only samples with a valid gas reading.
        if data.status & ffi::BME68X_GASM_VALID_MSK == 0 {
            return Ok(());
        }
        let inputs = bsec_inputs(now, &settings, &data, self.heat_source);
        let (outputs, status) = self.bsec.do_steps(&inputs)?;
        self.note_warning(status);

        let (accuracy, settled) = {
            let mut snap = self.snapshot.lock().unwrap();
            snap.record(&outputs, unix_now());
            (snap.iaq_accuracy(), snap.air_quality_valid())
        };
        self.maybe_save(accuracy, settled, false);
        Ok(())
    }

    fn note_warning(&self, status: bsec::Status) {
        if status > 0 {
            self.snapshot.lock().unwrap().bsec_warning(status);
        }
    }

    fn maybe_save(&mut self, accuracy: u8, settled: bool, force: bool) {
        if !self.store.claim_save(accuracy, settled, force) {
            return;
        }
        let result = self
            .bsec
            .get_state()
            .map_err(|e| e.to_string())
            .and_then(|blob| self.store.save(&blob, accuracy).map_err(|e| e.to_string()));
        match result {
            Ok(()) => eprintln!(
                "saved BSEC state (iaq_accuracy={accuracy}) to {}",
                self.store.path().display()
            ),
            Err(e) => eprintln!("failed to save BSEC state: {e}"),
        }
    }

    fn save_on_shutdown(&mut self) {
        let (accuracy, settled) = {
            let snap = self.snapshot.lock().unwrap();
            (snap.iaq_accuracy(), snap.air_quality_valid())
        };
        self.maybe_save(accuracy, settled, true);
    }
}

fn bsec_inputs(
    time_ns: i64,
    settings: &ffi::bsec_bme_settings_t,
    data: &ffi::bme68x_data,
    heat_source: f32,
) -> Vec<ffi::bsec_input_t> {
    let input = |sensor_id: u32, signal: f32| ffi::bsec_input_t {
        time_stamp: time_ns,
        signal,
        signal_dimensions: 1,
        sensor_id: sensor_id as u8,
    };
    let wanted = |id: u32| settings.process_data & (1 << (id - 1)) != 0;

    let mut inputs: Vec<_> = [
        (
            ffi::bsec_physical_sensor_t_BSEC_INPUT_HEATSOURCE,
            heat_source,
        ),
        (
            ffi::bsec_physical_sensor_t_BSEC_INPUT_TEMPERATURE,
            data.temperature,
        ),
        (
            ffi::bsec_physical_sensor_t_BSEC_INPUT_HUMIDITY,
            data.humidity,
        ),
        (
            ffi::bsec_physical_sensor_t_BSEC_INPUT_PRESSURE,
            data.pressure,
        ),
        (
            ffi::bsec_physical_sensor_t_BSEC_INPUT_GASRESISTOR,
            data.gas_resistance,
        ),
        // Always 0 in forced mode.
        (ffi::bsec_physical_sensor_t_BSEC_INPUT_PROFILE_PART, 0.0),
    ]
    .into_iter()
    .filter(|&(id, _)| wanted(id))
    .map(|(id, signal)| input(id, signal))
    .collect();
    // Bosch passes this in low-power mode regardless of process_data.
    inputs.push(input(
        ffi::bsec_physical_sensor_t_BSEC_INPUT_DISABLE_BASELINE_TRACKER,
        0.0,
    ));
    inputs
}

fn serve(listen: SocketAddr, snapshot: Arc<Mutex<Snapshot>>, info: Info) -> std::io::Result<()> {
    let server = tiny_http::Server::http(listen).map_err(std::io::Error::other)?;
    let mut registry = Registry::default();
    registry.register_collector(Box::new(metrics::Collector { snapshot, info }));
    thread::spawn(move || {
        let content_type = tiny_http::Header::from_bytes(
            "Content-Type",
            "application/openmetrics-text; version=1.0.0; charset=utf-8",
        )
        .unwrap();
        for req in server.incoming_requests() {
            let resp = if req.url() == "/metrics" {
                let mut body = String::new();
                let _ = prometheus_client::encoding::text::encode(&mut body, &registry);
                tiny_http::Response::from_string(body).with_header(content_type.clone())
            } else {
                tiny_http::Response::from_string("see /metrics\n").with_status_code(404)
            };
            let _ = req.respond(resp);
        }
    });
    Ok(())
}

fn sleep_until(deadline_ns: i64, stop: &AtomicBool) {
    while !stop.load(Ordering::Relaxed) {
        let left = deadline_ns - monotonic_ns();
        if left <= 0 {
            return;
        }
        thread::sleep(Duration::from_nanos(left.min(250_000_000) as u64));
    }
}

fn run(args: Args) -> Result<()> {
    let stop = Arc::new(AtomicBool::new(false));
    for sig in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(sig, Arc::clone(&stop))?;
    }

    let sensor = Bme68x::new(i2c::I2c::open(&args.bus, args.address)?)?;
    let mut bsec = Bsec::new()?;
    let bsec_version = bsec.version()?;
    let blob = config_blob();
    bsec.set_configuration(blob)?;

    let identity = Identity {
        bsec_version: bsec_version.clone(),
        config: CONFIG_NAME.into(),
        config_hash: state::fingerprint(blob),
        profile: args.profile.clone(),
    };
    let state_dir = args.state_dir.unwrap_or_else(default_state_dir);
    let mut store = StateStore::new(
        state_dir,
        identity,
        Duration::from_secs(args.state_interval),
        Duration::from_secs(args.state_max_age),
    );
    match store.load() {
        Ok(Loaded::TooWeak(accuracy)) => eprintln!(
            "saved BSEC state has iaq_accuracy={accuracy}, below {MIN_RESTORE_ACCURACY}; starting fresh"
        ),
        Ok(Loaded::Usable { blob, accuracy }) => {
            bsec.set_state(&blob)?;
            eprintln!(
                "restored BSEC state (iaq_accuracy={accuracy}) from {}",
                store.path().display()
            );
        }
        Ok(Loaded::Missing) => eprintln!(
            "no saved BSEC state at {}, starting uncalibrated",
            store.path().display()
        ),
        Err(e) => eprintln!("not restoring BSEC state: {e}"),
    }
    bsec.update_subscription(&metrics::subscribed_outputs(), SAMPLE_RATE)?;

    let info = Info {
        bsec_version,
        config: CONFIG_NAME.into(),
        profile: args.profile,
        variant: sensor.variant().into(),
    };
    let banner = format!(
        "{} on {} at {:#04x}, BSEC {} with {}, serving http://{}/metrics",
        info.variant,
        args.bus.display(),
        args.address,
        info.bsec_version,
        info.config,
        args.listen
    );
    let snapshot = Arc::new(Mutex::new(Snapshot::default()));
    serve(args.listen, Arc::clone(&snapshot), info)?;
    eprintln!("{banner}");

    let mut exporter = Exporter {
        sensor,
        bsec,
        store,
        snapshot,
        heat_source: args.heat_source,
        next_call: 0,
    };
    let mut failures = 0;
    while !stop.load(Ordering::Relaxed) {
        match exporter.cycle() {
            Ok(()) => failures = 0,
            Err(e) => {
                eprintln!("measurement cycle failed: {e}");
                exporter.snapshot.lock().unwrap().error(e.kind());
                failures += 1;
                if failures >= MAX_FAILURES {
                    exporter.save_on_shutdown();
                    return Err(e);
                }
                // Don't spin if BSEC's schedule didn't advance.
                exporter.next_call = exporter.next_call.max(monotonic_ns() + 1_000_000_000);
            }
        }
        sleep_until(exporter.next_call, &stop);
    }
    eprintln!("shutting down");
    exporter.save_on_shutdown();
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
