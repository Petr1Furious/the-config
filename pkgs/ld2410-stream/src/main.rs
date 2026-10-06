mod error;
mod protocol;

use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::process::ExitCode;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use clap::Parser;
use serde::Serialize;
use serialport::SerialPort;

use crate::error::{Error, Result};
use crate::protocol::{Decoder, Frame, Reading};

const ANSWER_TIMEOUT: Duration = Duration::from_secs(1);
const SILENCE_TIMEOUT: Duration = Duration::from_secs(5);
const CLIENT_WRITE_TIMEOUT: Duration = Duration::from_millis(200);

/// Streams LD2410 radar readings to TCP clients, one JSON object per line.
#[derive(Parser)]
struct Args {
    /// Serial device the sensor is wired to.
    #[arg(long, default_value = "/dev/ttyAMA0")]
    port: String,
    #[arg(long, default_value_t = 256000)]
    baud: u32,
    /// Address to serve the stream on.
    #[arg(long, default_value = "127.0.0.1:2410")]
    listen: SocketAddr,
}

#[derive(Serialize)]
struct Line<'a> {
    /// Unix time the reading arrived.
    t: f64,
    #[serde(flatten)]
    reading: &'a Reading,
}

struct Sensor {
    port: Box<dyn SerialPort>,
    decoder: Decoder,
}

impl Sensor {
    fn open(path: &str, baud: u32) -> Result<Self> {
        let port = serialport::new(path, baud)
            .timeout(Duration::from_millis(100))
            .open()?;
        Ok(Self {
            port,
            decoder: Decoder::default(),
        })
    }

    fn frames(&mut self) -> Result<Vec<Frame>> {
        let mut buf = [0; 512];
        match self.port.read(&mut buf) {
            Ok(n) => Ok(self.decoder.push(&buf[..n])),
            Err(e) if e.kind() == ErrorKind::TimedOut => Ok(Vec::new()),
            Err(e) => Err(e.into()),
        }
    }

    fn command(&mut self, command: u16, value: &[u8]) -> Result<Vec<u8>> {
        for _ in 0..3 {
            self.port.write_all(&protocol::command(command, value))?;
            let deadline = Instant::now() + ANSWER_TIMEOUT;
            while Instant::now() < deadline {
                for frame in self.frames()? {
                    match frame {
                        Frame::Ack {
                            command: c,
                            ok,
                            data,
                        } if c == command & 0xff => {
                            return if ok {
                                Ok(data)
                            } else {
                                Err(Error::Refused(command))
                            };
                        }
                        _ => {}
                    }
                }
            }
        }
        Err(Error::NoAnswer(command))
    }

    /// Switches on per-gate reporting, which the sensor forgets at power-off.
    /// Nothing is written to its flash.
    fn setup(&mut self) -> Result<()> {
        self.command(protocol::ENABLE_CONFIG, &[1, 0])?;
        let result = self.describe();
        self.command(protocol::END_CONFIG, &[])?;
        result
    }

    fn describe(&mut self) -> Result<()> {
        let firmware = self.command(protocol::READ_FIRMWARE, &[])?;
        let p = self.command(protocol::READ_PARAMETERS, &[])?;
        if p.len() < 24 {
            return Err(Error::ShortAnswer(protocol::READ_PARAMETERS));
        }
        eprintln!(
            "firmware {}, moving thresholds {:?}, stationary thresholds {:?}, hold {} s",
            protocol::firmware(&firmware).unwrap_or_default(),
            &p[4..13],
            &p[13..22],
            u16::from_le_bytes([p[22], p[23]])
        );
        self.command(protocol::ENABLE_ENGINEERING, &[])?;
        Ok(())
    }
}

type Clients = Arc<Mutex<Vec<TcpStream>>>;

fn accept(listener: TcpListener, clients: Clients) {
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        if stream.set_nodelay(true).is_ok()
            && stream.set_write_timeout(Some(CLIENT_WRITE_TIMEOUT)).is_ok()
        {
            clients.lock().unwrap().push(stream);
        }
    }
}

fn run(args: Args) -> Result<()> {
    let mut sensor = Sensor::open(&args.port, args.baud)?;
    sensor.setup()?;

    let listener = TcpListener::bind(args.listen)?;
    let clients = Clients::default();
    thread::spawn({
        let clients = Arc::clone(&clients);
        move || accept(listener, clients)
    });
    eprintln!(
        "{} at {} baud, serving on {}",
        args.port, args.baud, args.listen
    );

    let mut last = Instant::now();
    loop {
        for frame in sensor.frames()? {
            let Frame::Reading(reading) = frame else {
                continue;
            };
            // A power blip resets the sensor to plain reporting.
            if reading.gates.is_none() {
                return Err(Error::LeftEngineeringMode);
            }
            last = Instant::now();
            let t = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0.0, |d| d.as_secs_f64());
            let mut line = serde_json::to_vec(&Line {
                t,
                reading: &reading,
            })?;
            line.push(b'\n');
            clients
                .lock()
                .unwrap()
                .retain_mut(|client| client.write_all(&line).is_ok());
        }
        if last.elapsed() >= SILENCE_TIMEOUT {
            return Err(Error::Silent(SILENCE_TIMEOUT.as_secs()));
        }
    }
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
