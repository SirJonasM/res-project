use core::ptr::{read_volatile, write_volatile};

const LED_BASE: *mut u32 = 0x3000_0000 as *mut u32;

/// Represents a specific physical LED on the board (0 to 11).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Led {
    Led0  = 0,  Led1  = 1,  Led2  = 2,  Led3  = 3,
    Led4  = 4,  Led5  = 5,  Led6  = 6,  Led7  = 7,
    Led8  = 8,  Led9  = 9,  Led10 = 10, Led11 = 11,
}

/// A safe, user-friendly interface for controlling the 12 FPGA LEDs.
pub struct LedDriver;

impl LedDriver {
    /// Writes the raw 12-bit state directly to the register.
    /// Safely masks out any bits above the 12th bit to prevent invalid writes.
    pub fn write_raw(state: u16) {
        let masked_state = (state & 0x0FFF) as u32;
        unsafe {
            write_volatile(LED_BASE, masked_state);
        }
    }

    /// Reads the current raw 12-bit state of the LEDs.
    pub fn read_raw() -> u16 {
        unsafe {
            (read_volatile(LED_BASE) & 0x0FFF) as u16
        }
    }

    /// Turns a specific LED on or off without affecting the others.
    pub fn set(led: Led, turn_on: bool) {
        let current = Self::read_raw();
        let mask = 1 << (led as u8);
        
        let new_state = if turn_on {
            current | mask
        } else {
            current & !mask
        };
        
        Self::write_raw(new_state);
    }

    /// Toggles the state of a specific LED.
    pub fn toggle(led: Led) {
        let current = Self::read_raw();
        let mask = 1 << (led as u8);
        Self::write_raw(current ^ mask);
    }

    /// Turns all 12 LEDs off at once.
    pub fn all_off() {
        Self::write_raw(0);
    }

    /// Turns all 12 LEDs on at once.
    pub fn all_on() {
        Self::write_raw(0x0FFF);
    }
}
