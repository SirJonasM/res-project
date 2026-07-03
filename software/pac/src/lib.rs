#![no_std]
pub mod uart;
pub mod panic;
pub mod wdt;
pub use uart::UartLogger;

const LED_BASE: *mut u32 = 0x3000_0000 as *mut u32;

/// Turns the physical FPGA LED on or off
pub fn set_leds(state: u32) {
    unsafe {
        core::ptr::write_volatile(LED_BASE, state);
    }
}

pub fn read_leds() -> u32{
    unsafe {
        core::ptr::read_volatile(LED_BASE)
    }
}

