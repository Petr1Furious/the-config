use serde::Serialize;

const DATA_HEAD: [u8; 4] = [0xf4, 0xf3, 0xf2, 0xf1];
const DATA_TAIL: [u8; 4] = [0xf8, 0xf7, 0xf6, 0xf5];
const CMD_HEAD: [u8; 4] = [0xfd, 0xfc, 0xfb, 0xfa];
const CMD_TAIL: [u8; 4] = [0x04, 0x03, 0x02, 0x01];
const MAX_PAYLOAD: usize = 256;

pub const ENABLE_CONFIG: u16 = 0x00ff;
pub const END_CONFIG: u16 = 0x00fe;
pub const READ_PARAMETERS: u16 = 0x0061;
pub const ENABLE_ENGINEERING: u16 = 0x0062;
pub const READ_FIRMWARE: u16 = 0x00a0;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    None,
    Moving,
    Stationary,
    Both,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Target {
    pub cm: u16,
    pub energy: u8,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Gates {
    pub moving: Vec<u8>,
    pub stationary: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Reading {
    pub state: State,
    pub moving: Target,
    pub stationary: Target,
    pub detection_cm: u16,
    /// Per-gate energies, light level and OUT pin; engineering mode only.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gates: Option<Gates>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub light: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub out: Option<bool>,
}

#[derive(Debug, PartialEq)]
pub enum Frame {
    Reading(Reading),
    /// Answer to a command: the command word and what follows the status.
    Ack {
        command: u16,
        ok: bool,
        data: Vec<u8>,
    },
}

fn le16(b: &[u8]) -> u16 {
    u16::from_le_bytes([b[0], b[1]])
}

fn reading(p: &[u8]) -> Option<Reading> {
    if p.len() < 13 || p[1] != 0xaa {
        return None;
    }
    let state = match p[2] {
        0 => State::None,
        1 => State::Moving,
        2 => State::Stationary,
        3 => State::Both,
        _ => return None,
    };
    let mut reading = Reading {
        state,
        moving: Target {
            cm: le16(&p[3..]),
            energy: p[5],
        },
        stationary: Target {
            cm: le16(&p[6..]),
            energy: p[8],
        },
        detection_cm: le16(&p[9..]),
        gates: None,
        light: None,
        out: None,
    };
    if p[0] == 0x01 {
        let (moving, stationary) = (p[11] as usize + 1, p[12] as usize + 1);
        let rest = &p[13..];
        if rest.len() >= moving + stationary + 2 {
            reading.gates = Some(Gates {
                moving: rest[..moving].to_vec(),
                stationary: rest[moving..moving + stationary].to_vec(),
            });
            reading.light = Some(rest[moving + stationary]);
            reading.out = Some(rest[moving + stationary + 1] != 0);
        }
    }
    Some(reading)
}

fn ack(p: &[u8]) -> Option<Frame> {
    if p.len() < 4 || p[1] != 0x01 {
        return None;
    }
    Some(Frame::Ack {
        command: p[0] as u16,
        ok: le16(&p[2..]) == 0,
        data: p[4..].to_vec(),
    })
}

#[derive(Default)]
pub struct Decoder {
    buf: Vec<u8>,
}

impl Decoder {
    pub fn push(&mut self, bytes: &[u8]) -> Vec<Frame> {
        self.buf.extend_from_slice(bytes);
        let mut frames = Vec::new();
        loop {
            let start = self
                .buf
                .windows(4)
                .position(|w| w == DATA_HEAD || w == CMD_HEAD);
            let Some(start) = start else {
                let keep = self.buf.len().min(3);
                self.buf.drain(..self.buf.len() - keep);
                break;
            };
            self.buf.drain(..start);
            if self.buf.len() < 6 {
                break;
            }
            let size = le16(&self.buf[4..]) as usize;
            if size > MAX_PAYLOAD {
                self.buf.drain(..1);
                continue;
            }
            if self.buf.len() < size + 10 {
                break;
            }
            let payload = &self.buf[6..6 + size];
            let tail = &self.buf[6 + size..10 + size];
            let frame = if self.buf[..4] == DATA_HEAD && tail == DATA_TAIL {
                reading(payload).map(Frame::Reading)
            } else if self.buf[..4] == CMD_HEAD && tail == CMD_TAIL {
                ack(payload)
            } else {
                None
            };
            match frame {
                Some(frame) => {
                    frames.push(frame);
                    self.buf.drain(..size + 10);
                }
                None => {
                    self.buf.drain(..1);
                }
            }
        }
        frames
    }
}

pub fn command(command: u16, value: &[u8]) -> Vec<u8> {
    let mut out = CMD_HEAD.to_vec();
    out.extend((value.len() as u16 + 2).to_le_bytes());
    out.extend(command.to_le_bytes());
    out.extend(value);
    out.extend(CMD_TAIL);
    out
}

/// Firmware version from a READ_FIRMWARE answer, as the vendor app prints it.
pub fn firmware(data: &[u8]) -> Option<String> {
    (data.len() >= 8).then(|| {
        format!(
            "V{}.{:02}.{:02x}{:02x}{:02x}{:02x}",
            data[3], data[2], data[7], data[6], data[5], data[4]
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        s.split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).unwrap())
            .collect()
    }

    const BASIC: &str = "f4 f3 f2 f1 0d 00 02 aa 03 27 00 43 1e 00 64 28 00 55 00 f8 f7 f6 f5";

    fn engineering() -> Vec<u8> {
        let mut payload = hex("01 aa 02 4b 00 00 4b 00 64 b2 00 08 08");
        payload.extend([11, 9, 8, 14, 10, 3, 3, 5, 6]);
        payload.extend([0, 0, 100, 93, 100, 72, 27, 28, 21]);
        payload.extend([7, 1, 0x55, 0x00]);
        let mut frame = DATA_HEAD.to_vec();
        frame.extend((payload.len() as u16).to_le_bytes());
        frame.extend(payload);
        frame.extend(DATA_TAIL);
        frame
    }

    #[test]
    fn decodes_a_basic_reading() {
        let frames = Decoder::default().push(&hex(BASIC));
        let [Frame::Reading(r)] = frames.as_slice() else {
            panic!("{frames:?}")
        };
        assert_eq!(r.state, State::Both);
        assert_eq!(r.moving, Target { cm: 39, energy: 67 });
        assert_eq!(
            r.stationary,
            Target {
                cm: 30,
                energy: 100
            }
        );
        assert_eq!(r.detection_cm, 40);
        assert_eq!(r.gates, None);
    }

    #[test]
    fn decodes_an_engineering_reading() {
        let frames = Decoder::default().push(&engineering());
        let [Frame::Reading(r)] = frames.as_slice() else {
            panic!("{frames:?}")
        };
        assert_eq!(r.state, State::Stationary);
        assert_eq!(
            r.stationary,
            Target {
                cm: 75,
                energy: 100
            }
        );
        assert_eq!(r.detection_cm, 178);
        let gates = r.gates.as_ref().unwrap();
        assert_eq!(gates.moving, [11, 9, 8, 14, 10, 3, 3, 5, 6]);
        assert_eq!(gates.stationary[2], 100);
        assert_eq!(r.light, Some(7));
        assert_eq!(r.out, Some(true));
    }

    #[test]
    fn survives_split_reads_and_garbage() {
        let mut stream = hex("00 f4 f3 99");
        stream.extend(hex(BASIC));
        stream.extend(engineering());
        let mut decoder = Decoder::default();
        let frames: Vec<_> = stream.chunks(5).flat_map(|c| decoder.push(c)).collect();
        assert_eq!(frames.len(), 2);
    }

    #[test]
    fn decodes_an_ack() {
        let bytes = hex("fd fc fb fa 0c 00 a0 01 00 00 00 01 44 02 17 09 07 25 04 03 02 01");
        let frames = Decoder::default().push(&bytes);
        let [Frame::Ack { command, ok, data }] = frames.as_slice() else {
            panic!("{frames:?}")
        };
        assert_eq!((*command, *ok), (READ_FIRMWARE & 0xff, true));
        assert_eq!(firmware(data).unwrap(), "V2.68.25070917");
    }

    #[test]
    fn encodes_a_command() {
        assert_eq!(
            command(ENABLE_CONFIG, &[1, 0]),
            hex("fd fc fb fa 04 00 ff 00 01 00 04 03 02 01")
        );
    }

    #[test]
    fn readings_serialise_compactly() {
        let frames = Decoder::default().push(&hex(BASIC));
        let Frame::Reading(r) = &frames[0] else {
            panic!()
        };
        assert_eq!(
            serde_json::to_string(r).unwrap(),
            r#"{"state":"both","moving":{"cm":39,"energy":67},"stationary":{"cm":30,"energy":100},"detection_cm":40}"#
        );
    }
}
