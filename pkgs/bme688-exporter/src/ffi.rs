#![allow(
    dead_code,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals
)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

// Defined through UINT8_C()/INT8_C(), which bindgen skips.
pub const BME68X_OK: i8 = 0;
pub const BME68X_W_NO_NEW_DATA: i8 = 2;
pub const BME68X_SLEEP_MODE: u8 = 0;
pub const BME68X_FORCED_MODE: u8 = 1;
pub const BME68X_ENABLE: u8 = 1;
pub const BME68X_DISABLE: u8 = 0;
pub const BME68X_FILTER_OFF: u8 = 0;
pub const BME68X_ODR_NONE: u8 = 8;
pub const BME68X_GASM_VALID_MSK: u8 = 0x20;
