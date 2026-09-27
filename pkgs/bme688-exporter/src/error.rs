use std::io;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error("{op} failed with code {code}{}", cause_suffix(.cause))]
    Bme68x {
        op: &'static str,
        code: i8,
        cause: Option<io::Error>,
    },
    #[error("{op} failed with BSEC code {code}")]
    Bsec { op: &'static str, code: i32 },
}

fn cause_suffix(cause: &Option<io::Error>) -> String {
    cause
        .as_ref()
        .map(|e| format!(" ({e})"))
        .unwrap_or_default()
}

impl Error {
    pub fn kind(&self) -> &'static str {
        match self {
            Error::Io(_) => "io",
            Error::Bme68x { .. } => "sensor",
            Error::Bsec { .. } => "bsec",
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;
