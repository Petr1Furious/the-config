#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Serial(#[from] serialport::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("no answer to command {0:#06x}")]
    NoAnswer(u16),
    #[error("command {0:#06x} refused")]
    Refused(u16),
    #[error("short answer to command {0:#06x}")]
    ShortAnswer(u16),
    #[error("no readings for {0} s")]
    Silent(u64),
    #[error("sensor left engineering mode")]
    LeftEngineeringMode,
}

pub type Result<T> = std::result::Result<T, Error>;
