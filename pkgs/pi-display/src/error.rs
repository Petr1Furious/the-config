#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] ureq::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Time(#[from] jiff::Error),
    #[error("display: {0}")]
    Display(String),
    #[error("opposite stop {0} lists no departures to learn directions from")]
    NoOppositeDepartures(String),
}

pub type Result<T> = std::result::Result<T, Error>;
