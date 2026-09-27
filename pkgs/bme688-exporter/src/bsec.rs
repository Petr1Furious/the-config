use std::ffi::c_void;

use crate::error::{Error, Result};
use crate::ffi;

pub struct Bsec {
    // u64 for 8-byte alignment; never resized, as BSEC holds a pointer into it.
    inst: Vec<u64>,
}

pub type Status = i32;

fn check(op: &'static str, code: ffi::bsec_library_return_t) -> Result<Status> {
    if code < 0 {
        Err(Error::Bsec { op, code })
    } else {
        Ok(code)
    }
}

fn work_buffer() -> Vec<u8> {
    vec![0; ffi::BSEC_MAX_WORKBUFFER_SIZE as usize]
}

impl Bsec {
    pub fn new() -> Result<Self> {
        let size = unsafe { ffi::bsec_get_instance_size() };
        let mut bsec = Self {
            inst: vec![0; size.div_ceil(8)],
        };
        check("bsec_init", unsafe { ffi::bsec_init(bsec.ptr()) })?;
        Ok(bsec)
    }

    fn ptr(&mut self) -> *mut c_void {
        self.inst.as_mut_ptr().cast()
    }

    pub fn version(&mut self) -> Result<String> {
        let mut v = ffi::bsec_version_t::default();
        check("bsec_get_version", unsafe {
            ffi::bsec_get_version(self.ptr(), &mut v)
        })?;
        Ok(format!(
            "{}.{}.{}.{}",
            v.major, v.minor, v.major_bugfix, v.minor_bugfix
        ))
    }

    pub fn set_configuration(&mut self, blob: &[u8]) -> Result<Status> {
        let mut work = work_buffer();
        check("bsec_set_configuration", unsafe {
            ffi::bsec_set_configuration(
                self.ptr(),
                blob.as_ptr(),
                blob.len() as u32,
                work.as_mut_ptr(),
                work.len() as u32,
            )
        })
    }

    pub fn set_state(&mut self, blob: &[u8]) -> Result<Status> {
        let mut work = work_buffer();
        check("bsec_set_state", unsafe {
            ffi::bsec_set_state(
                self.ptr(),
                blob.as_ptr(),
                blob.len() as u32,
                work.as_mut_ptr(),
                work.len() as u32,
            )
        })
    }

    pub fn get_state(&mut self) -> Result<Vec<u8>> {
        let mut state = vec![0u8; ffi::BSEC_MAX_STATE_BLOB_SIZE as usize];
        let mut work = work_buffer();
        let mut len = 0u32;
        check("bsec_get_state", unsafe {
            ffi::bsec_get_state(
                self.ptr(),
                0,
                state.as_mut_ptr(),
                state.len() as u32,
                work.as_mut_ptr(),
                work.len() as u32,
                &mut len,
            )
        })?;
        state.truncate(len as usize);
        Ok(state)
    }

    pub fn update_subscription(&mut self, outputs: &[u32], sample_rate: f32) -> Result<Status> {
        let requested: Vec<_> = outputs
            .iter()
            .map(|&id| ffi::bsec_sensor_configuration_t {
                sample_rate,
                sensor_id: id as u8,
            })
            .collect();
        let mut required =
            [ffi::bsec_sensor_configuration_t::default(); ffi::BSEC_MAX_PHYSICAL_SENSOR as usize];
        let mut n_required = required.len() as u8;
        check("bsec_update_subscription", unsafe {
            ffi::bsec_update_subscription(
                self.ptr(),
                requested.as_ptr(),
                requested.len() as u8,
                required.as_mut_ptr(),
                &mut n_required,
            )
        })
    }

    pub fn sensor_control(&mut self, time_ns: i64) -> Result<(ffi::bsec_bme_settings_t, Status)> {
        let mut settings = ffi::bsec_bme_settings_t::default();
        let status = check("bsec_sensor_control", unsafe {
            ffi::bsec_sensor_control(self.ptr(), time_ns, &mut settings)
        })?;
        Ok((settings, status))
    }

    pub fn do_steps(
        &mut self,
        inputs: &[ffi::bsec_input_t],
    ) -> Result<(Vec<ffi::bsec_output_t>, Status)> {
        let mut outputs = vec![ffi::bsec_output_t::default(); ffi::BSEC_NUMBER_OUTPUTS as usize];
        let mut n = outputs.len() as u8;
        let status = check("bsec_do_steps", unsafe {
            ffi::bsec_do_steps(
                self.ptr(),
                inputs.as_ptr(),
                inputs.len() as u8,
                outputs.as_mut_ptr(),
                &mut n,
            )
        })?;
        outputs.truncate(n as usize);
        Ok((outputs, status))
    }
}
