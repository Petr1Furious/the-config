use std::collections::{BTreeMap, HashMap};
use std::fmt;
use std::sync::{Arc, Mutex};

use prometheus_client::encoding::{DescriptorEncoder, EncodeMetric};
use prometheus_client::metrics::MetricType;
use prometheus_client::metrics::counter::ConstCounter;
use prometheus_client::metrics::gauge::ConstGauge;
use prometheus_client::metrics::info::Info as InfoMetric;

use crate::ffi;

/// Samples after each start with air-quality metrics withheld and no state saves:
/// BSEC's 380 °C burn-off leaves gas resistance high for ~5 minutes, while BSEC
/// already reports full accuracy.
const STARTUP_SAMPLES: u64 = 160;

struct Gauge {
    output: u32,
    name: &'static str,
    help: &'static str,
    scale: f64,
    air_quality: bool,
}

const GAUGES: &[Gauge] = &[
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_TEMPERATURE,
        name: "bme688_temperature_celsius",
        help: "Compensated temperature.",
        scale: 1.0,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RAW_TEMPERATURE,
        name: "bme688_raw_temperature_celsius",
        help: "Raw temperature.",
        scale: 1.0,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_SENSOR_HEAT_COMPENSATED_HUMIDITY,
        name: "bme688_humidity_ratio",
        help: "Compensated relative humidity.",
        scale: 0.01,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RAW_HUMIDITY,
        name: "bme688_raw_humidity_ratio",
        help: "Raw relative humidity.",
        scale: 0.01,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RAW_PRESSURE,
        name: "bme688_pressure_pascals",
        help: "Barometric pressure.",
        scale: 1.0,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RAW_GAS,
        name: "bme688_gas_resistance_ohms",
        help: "Raw gas resistance.",
        scale: 1.0,
        air_quality: false,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_COMPENSATED_GAS,
        name: "bme688_gas_compensated_log10_ohms",
        help: "Compensated gas resistance, log10.",
        scale: 1.0,
        air_quality: true,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_IAQ,
        name: "bme688_iaq",
        help: "Indoor air quality index.",
        scale: 1.0,
        air_quality: true,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_STATIC_IAQ,
        name: "bme688_static_iaq",
        help: "Static indoor air quality index.",
        scale: 1.0,
        air_quality: true,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_GAS_PERCENTAGE,
        name: "bme688_gas_range_ratio",
        help: "Gas reading's position in the learned range.",
        scale: 0.01,
        air_quality: true,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_CO2_EQUIVALENT,
        name: "bme688_co2_equivalent_ppm",
        help: "CO2 equivalent.",
        scale: 1.0,
        air_quality: true,
    },
    Gauge {
        output: ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_BREATH_VOC_EQUIVALENT,
        name: "bme688_breath_voc_equivalent_ppm",
        help: "Breath-VOC equivalent.",
        scale: 1.0,
        air_quality: true,
    },
];

pub fn subscribed_outputs() -> Vec<u32> {
    let mut outputs: Vec<u32> = GAUGES.iter().map(|g| g.output).collect();
    outputs.push(ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_STABILIZATION_STATUS);
    outputs.push(ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RUN_IN_STATUS);
    outputs
}

#[derive(Debug)]
pub struct Info {
    pub bsec_version: String,
    pub config: String,
    pub profile: String,
    pub variant: String,
}

#[derive(Debug, Default)]
pub struct Snapshot {
    outputs: HashMap<u32, (f32, u8)>,
    last_sample_unix: Option<f64>,
    samples: u64,
    errors: BTreeMap<&'static str, u64>,
    bsec_warnings: BTreeMap<i32, u64>,
}

impl Snapshot {
    pub fn record(&mut self, outputs: &[ffi::bsec_output_t], unix_time: f64) {
        for o in outputs {
            self.outputs
                .insert(u32::from(o.sensor_id), (o.signal, o.accuracy));
        }
        self.last_sample_unix = Some(unix_time);
        self.samples += 1;
    }

    pub fn error(&mut self, kind: &'static str) {
        *self.errors.entry(kind).or_default() += 1;
    }

    pub fn bsec_warning(&mut self, code: i32) {
        *self.bsec_warnings.entry(code).or_default() += 1;
    }

    fn flag(&self, output: u32) -> Option<bool> {
        self.outputs.get(&output).map(|&(v, _)| v >= 1.0)
    }

    pub fn run_in_complete(&self) -> bool {
        self.flag(ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RUN_IN_STATUS) == Some(true)
    }

    pub fn air_quality_valid(&self) -> bool {
        self.run_in_complete() && self.samples >= STARTUP_SAMPLES
    }

    pub fn iaq_accuracy(&self) -> u8 {
        self.outputs
            .get(&ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_IAQ)
            .map_or(0, |&(_, acc)| acc)
    }
}

/// Encodes on every scrape instead of registering gauges, so a metric without a
/// valid value is absent rather than 0.
#[derive(Debug)]
pub struct Collector {
    pub snapshot: Arc<Mutex<Snapshot>>,
    pub info: Info,
}

impl prometheus_client::collector::Collector for Collector {
    fn encode(&self, mut enc: DescriptorEncoder) -> fmt::Result {
        let snap = self.snapshot.lock().unwrap();
        let valid = snap.air_quality_valid();

        for g in GAUGES {
            if g.air_quality && !valid {
                continue;
            }
            if let Some(&(v, _)) = snap.outputs.get(&g.output) {
                gauge(&mut enc, g.name, g.help, f64::from(v) * g.scale)?;
            }
        }
        if valid {
            gauge(
                &mut enc,
                "bme688_iaq_accuracy",
                "IAQ accuracy, 0-3.",
                f64::from(snap.iaq_accuracy()),
            )?;
        }
        for (name, output, help) in [
            (
                "bme688_run_in_complete",
                ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RUN_IN_STATUS,
                "Gas sensor run-in complete.",
            ),
            (
                "bme688_stabilized",
                ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_STABILIZATION_STATUS,
                "Gas sensor stabilization complete.",
            ),
        ] {
            if let Some(f) = snap.flag(output) {
                gauge(&mut enc, name, help, f64::from(u8::from(f)))?;
            }
        }
        if let Some(t) = snap.last_sample_unix {
            gauge(
                &mut enc,
                "bme688_last_sample_timestamp_seconds",
                "Time of the last sample.",
                t,
            )?;
        }

        // OpenMetrics adds the _total and _info suffixes.
        ConstCounter::new(snap.samples).encode(enc.encode_descriptor(
            "bme688_samples",
            "Samples processed.",
            None,
            MetricType::Counter,
        )?)?;
        let mut errors = enc.encode_descriptor(
            "bme688_errors",
            "Failed measurement cycles.",
            None,
            MetricType::Counter,
        )?;
        for kind in ["io", "sensor", "bsec"] {
            let n = snap.errors.get(kind).copied().unwrap_or(0);
            ConstCounter::new(n).encode(errors.encode_family(&[("kind", kind)])?)?;
        }
        let mut warnings = enc.encode_descriptor(
            "bme688_bsec_warnings",
            "BSEC warnings by code.",
            None,
            MetricType::Counter,
        )?;
        for (code, &n) in &snap.bsec_warnings {
            ConstCounter::new(n).encode(warnings.encode_family(&[("code", code.to_string())])?)?;
        }
        InfoMetric::new([
            ("version", env!("CARGO_PKG_VERSION")),
            ("bsec_version", self.info.bsec_version.as_str()),
            ("config", self.info.config.as_str()),
            ("profile", self.info.profile.as_str()),
            ("variant", self.info.variant.as_str()),
        ])
        .encode(enc.encode_descriptor(
            "bme688_build",
            "Exporter configuration.",
            None,
            MetricType::Info,
        )?)
    }
}

fn gauge(enc: &mut DescriptorEncoder, name: &str, help: &str, value: f64) -> fmt::Result {
    ConstGauge::new(value).encode(enc.encode_descriptor(name, help, None, MetricType::Gauge)?)
}

#[cfg(test)]
mod tests {
    use prometheus_client::registry::Registry;

    use super::*;

    fn scrape(snapshot: Snapshot) -> String {
        let mut registry = Registry::default();
        registry.register_collector(Box::new(Collector {
            snapshot: Arc::new(Mutex::new(snapshot)),
            info: Info {
                bsec_version: "3.3.0.1".into(),
                config: "test_config".into(),
                profile: "indoor".into(),
                variant: "BME688".into(),
            },
        }));
        let mut out = String::new();
        prometheus_client::encoding::text::encode(&mut out, &registry).unwrap();
        out
    }

    fn snapshot_after(samples: u64, run_in: bool) -> Snapshot {
        let output = |id: u32, signal: f32| ffi::bsec_output_t {
            sensor_id: id as u8,
            signal,
            accuracy: 3,
            ..Default::default()
        };
        let outputs = [
            output(ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_IAQ, 42.0),
            output(ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RAW_TEMPERATURE, 21.5),
            output(
                ffi::bsec_virtual_sensor_t_BSEC_OUTPUT_RUN_IN_STATUS,
                if run_in { 1.0 } else { 0.0 },
            ),
        ];
        let mut snap = Snapshot::default();
        for _ in 0..samples {
            snap.record(&outputs, 0.0);
        }
        snap
    }

    #[test]
    fn air_quality_is_withheld_during_startup() {
        let text = scrape(snapshot_after(STARTUP_SAMPLES - 1, true));
        assert!(!text.contains("bme688_iaq "), "{text}");
        assert!(!text.contains("bme688_iaq_accuracy"), "{text}");
        assert!(
            text.contains("bme688_raw_temperature_celsius 21.5"),
            "{text}"
        );
    }

    #[test]
    fn air_quality_is_withheld_during_run_in() {
        let text = scrape(snapshot_after(STARTUP_SAMPLES + 5, false));
        assert!(!text.contains("bme688_iaq "), "{text}");
    }

    #[test]
    fn air_quality_is_shown_after_startup() {
        let text = scrape(snapshot_after(STARTUP_SAMPLES, true));
        assert!(text.contains("bme688_iaq 42.0"), "{text}");
        assert!(text.contains("bme688_iaq_accuracy 3.0"), "{text}");
    }

    #[test]
    fn counters_and_info_follow_openmetrics() {
        let text = scrape(snapshot_after(STARTUP_SAMPLES, true));
        assert!(
            text.contains(&format!("bme688_samples_total {STARTUP_SAMPLES}")),
            "{text}"
        );
        assert!(
            text.contains("bme688_errors_total{kind=\"io\"} 0"),
            "{text}"
        );
        assert!(text.contains("bme688_build_info{version=\""), "{text}");
        assert!(text.ends_with("# EOF\n"), "{text}");
    }
}
