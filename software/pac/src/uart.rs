use core::fmt;

pub struct UartLogger;

const UART_DATA: *mut u32 = 0x2000_0000 as *mut u32;
const UART_STATUS: *const u32 = 0x2000_0004 as *const u32;

pub fn read_char() -> Option<u8> {
    unsafe {
        if (core::ptr::read_volatile(UART_STATUS) & 0x01) == 0 {
            return None;
        }
        Some(core::ptr::read_volatile(UART_DATA as *const u8))
    }
}

/// Writes a single byte to the UART FIFO, waiting if it's full.
pub fn uart_putchar(c: u8) {
    unsafe {
        // Wait until the transmit FIFO is not full (assuming 0x02 means full)
        while (core::ptr::read_volatile(UART_STATUS) & 0x02) != 0 {
            core::hint::spin_loop();
        }
        core::ptr::write_volatile(UART_DATA, c as u32);
    }
}

// 1. Implement core::fmt::Write so UartLogger can handle formatted strings
impl fmt::Write for UartLogger {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for c in s.chars() {
            // Optional: Convert LF (\n) to CRLF (\r\n) for serial terminals
            if c == '\n' {
                uart_putchar(b'\r' );
            }
            uart_putchar(c as u8);
        }
        Ok(())
    }
}

// 2. Define the macros
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {{
        use core::fmt::Write;
        // Create a local instance of the logger and write to it
        let _ = write!($crate::UartLogger, $($arg)*);
    }};
}

#[macro_export]
macro_rules! println {
    () => {
        $crate::print!("\n")
    };
    ($($arg:tt)*) => {{
        use core::fmt::Write;
        let _ = writeln!($crate::UartLogger, $($arg)*);
    }};
}
