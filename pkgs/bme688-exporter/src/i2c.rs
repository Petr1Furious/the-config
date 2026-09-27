use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::path::Path;

const I2C_SLAVE: libc::c_ulong = 0x0703;

pub struct I2c {
    file: File,
    /// Kept to report after the SensorAPI reduces it to an error code.
    pub last_error: Option<io::Error>,
}

impl I2c {
    pub fn open(bus: &Path, address: u8) -> io::Result<Self> {
        let file = OpenOptions::new().read(true).write(true).open(bus)?;
        let fd = file.as_raw_fd();

        if unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            let err = io::Error::last_os_error();
            return Err(if err.kind() == io::ErrorKind::WouldBlock {
                io::Error::other(format!(
                    "{} is locked by another process driving the sensor",
                    bus.display()
                ))
            } else {
                err
            });
        }

        if unsafe { libc::ioctl(fd, I2C_SLAVE as _, libc::c_ulong::from(address)) } < 0 {
            return Err(io::Error::last_os_error());
        }

        Ok(Self {
            file,
            last_error: None,
        })
    }

    pub fn read_regs(&mut self, reg: u8, buf: &mut [u8]) -> io::Result<()> {
        self.transfer(&[reg])?;
        let n = self.file.read(buf)?;
        if n != buf.len() {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "short I2C read",
            ));
        }
        Ok(())
    }

    pub fn write_regs(&mut self, reg: u8, data: &[u8]) -> io::Result<()> {
        let mut msg = Vec::with_capacity(data.len() + 1);
        msg.push(reg);
        msg.extend_from_slice(data);
        self.transfer(&msg)
    }

    // One write() is one bus transaction; write_all could split it.
    fn transfer(&mut self, msg: &[u8]) -> io::Result<()> {
        let n = self.file.write(msg)?;
        if n != msg.len() {
            return Err(io::Error::new(io::ErrorKind::WriteZero, "short I2C write"));
        }
        Ok(())
    }
}
