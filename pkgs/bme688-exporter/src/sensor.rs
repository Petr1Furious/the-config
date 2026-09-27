use std::ffi::c_void;
use std::thread;
use std::time::Duration;

use crate::error::{Error, Result};
use crate::ffi;
use crate::i2c::I2c;

pub struct Bme68x {
    dev: ffi::bme68x_dev,
    conf: ffi::bme68x_conf,
    // Boxed so the pointer the SensorAPI keeps in `dev.intf_ptr` stays valid.
    i2c: Box<I2c>,
}

impl Bme68x {
    pub fn new(i2c: I2c) -> Result<Self> {
        let mut i2c = Box::new(i2c);
        let dev = ffi::bme68x_dev {
            intf: ffi::bme68x_intf_BME68X_I2C_INTF,
            intf_ptr: (&mut *i2c as *mut I2c).cast(),
            read: Some(read_cb),
            write: Some(write_cb),
            delay_us: Some(delay_cb),
            amb_temp: 25,
            ..Default::default()
        };
        let mut sensor = Self {
            dev,
            conf: Default::default(),
            i2c,
        };
        let rslt = unsafe { ffi::bme68x_init(&mut sensor.dev) };
        sensor.check("bme68x_init", rslt)?;
        Ok(sensor)
    }

    pub fn variant(&self) -> &'static str {
        if self.dev.variant_id == 1 {
            "BME688"
        } else {
            "BME680"
        }
    }

    pub fn trigger_forced(&mut self, s: &ffi::bsec_bme_settings_t) -> Result<Duration> {
        let rslt = unsafe { ffi::bme68x_set_op_mode(ffi::BME68X_SLEEP_MODE, &mut self.dev) };
        self.check("bme68x_set_op_mode(sleep)", rslt)?;

        self.conf = ffi::bme68x_conf {
            os_hum: s.humidity_oversampling,
            os_temp: s.temperature_oversampling,
            os_pres: s.pressure_oversampling,
            filter: ffi::BME68X_FILTER_OFF,
            odr: ffi::BME68X_ODR_NONE,
        };
        let rslt = unsafe { ffi::bme68x_set_conf(&mut self.conf, &mut self.dev) };
        self.check("bme68x_set_conf", rslt)?;

        let run_gas = s.run_gas == 1;
        let heatr = ffi::bme68x_heatr_conf {
            enable: if run_gas {
                ffi::BME68X_ENABLE
            } else {
                ffi::BME68X_DISABLE
            },
            heatr_temp: s.heater_temperature,
            heatr_dur: s.heater_duration,
            ..Default::default()
        };
        let rslt =
            unsafe { ffi::bme68x_set_heatr_conf(ffi::BME68X_FORCED_MODE, &heatr, &mut self.dev) };
        self.check("bme68x_set_heatr_conf", rslt)?;

        let rslt = unsafe { ffi::bme68x_set_op_mode(ffi::BME68X_FORCED_MODE, &mut self.dev) };
        self.check("bme68x_set_op_mode(forced)", rslt)?;

        let meas_us = unsafe {
            ffi::bme68x_get_meas_dur(ffi::BME68X_FORCED_MODE, &mut self.conf, &mut self.dev)
        };
        let heat_us = if run_gas {
            u32::from(s.heater_duration) * 1000
        } else {
            0
        };
        Ok(Duration::from_micros(u64::from(meas_us + heat_us)))
    }

    pub fn read(&mut self) -> Result<Option<ffi::bme68x_data>> {
        let mut data = ffi::bme68x_data::default();
        let mut n = 0u8;
        let rslt = unsafe {
            ffi::bme68x_get_data(ffi::BME68X_FORCED_MODE, &mut data, &mut n, &mut self.dev)
        };
        if rslt == ffi::BME68X_W_NO_NEW_DATA || n == 0 {
            return Ok(None);
        }
        self.check("bme68x_get_data", rslt)?;
        Ok(Some(data))
    }

    fn check(&mut self, op: &'static str, code: i8) -> Result<()> {
        if code < ffi::BME68X_OK {
            return Err(Error::Bme68x {
                op,
                code,
                cause: self.i2c.last_error.take(),
            });
        }
        Ok(())
    }
}

// These must never panic: unwinding out of an extern "C" fn aborts the process.

unsafe extern "C" fn read_cb(reg: u8, data: *mut u8, len: u32, intf_ptr: *mut c_void) -> i8 {
    let i2c = unsafe { &mut *intf_ptr.cast::<I2c>() };
    let buf = unsafe { std::slice::from_raw_parts_mut(data, len as usize) };
    match i2c.read_regs(reg, buf) {
        Ok(()) => 0,
        Err(e) => {
            i2c.last_error = Some(e);
            -1
        }
    }
}

unsafe extern "C" fn write_cb(reg: u8, data: *const u8, len: u32, intf_ptr: *mut c_void) -> i8 {
    let i2c = unsafe { &mut *intf_ptr.cast::<I2c>() };
    let buf = unsafe { std::slice::from_raw_parts(data, len as usize) };
    match i2c.write_regs(reg, buf) {
        Ok(()) => 0,
        Err(e) => {
            i2c.last_error = Some(e);
            -1
        }
    }
}

unsafe extern "C" fn delay_cb(period_us: u32, _intf_ptr: *mut c_void) {
    thread::sleep(Duration::from_micros(u64::from(period_us)));
}
