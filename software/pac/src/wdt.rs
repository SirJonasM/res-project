// Core addresses from the NEORV32 manual
pub const NEORV32_WDT_CTRL: *mut u32 = 0xFFFB_0000 as *mut u32;
pub const NEORV32_WDT_RESET: *mut u32 = 0xFFFB_0004 as *mut u32;

// The hardwired password required exclusively for feeding the watchdog
const WDT_PASSWORD: u32 = 0x709D1AB3;

const WDT_CTRL_EN: u32 = 1 << 0;
const WDT_CTRL_LOCK: u32 = 1 << 1;

/// Initializes the NEORV32 watchdog with a custom timeout value.
/// 
/// `timeout_val` is the raw 24-bit value calculated relative to your clock speed.
/// For a 5-second timeout, pass: `(5 * CLOCK_FREQUENCY_HZ) / 4096`
pub fn watchdog_init(timeout_val: u32) {
    unsafe {
        // timeout_val must fit inside 24 bits (bits 31:8 of the register)
        let timeout_bits = (timeout_val & 0xFF_FFFF) << 8;
        
        // Combine ONLY the timeout bits and the enable flag.
        // Do NOT include WDT_PASSWORD here; it will corrupt the configuration block.
        let config = timeout_bits | WDT_CTRL_EN;
        
        core::ptr::write_volatile(NEORV32_WDT_CTRL, config);
    }
}

/// Feed the watchdog to prevent a system hardware reset.
/// This must be called periodically before the timeout counter reaches its max value.
#[inline(always)]
pub fn watchdog_feed() {
    unsafe {
        // The RESET register expects the exact 32-bit hardware password sequence
        core::ptr::write_volatile(NEORV32_WDT_RESET, WDT_PASSWORD);
    }
}

/// Force a clean system hardware reset instantly by violating the configuration lock.
pub fn trigger_fpga_reset() -> ! {
    unsafe {
        // 1. Force enable and lock the configuration instantly without password bits
        core::ptr::write_volatile(NEORV32_WDT_CTRL, WDT_CTRL_EN | WDT_CTRL_LOCK);
        
        // 2. Immediately write to the locked register again -> Triggers instant hardware reset
        core::ptr::write_volatile(NEORV32_WDT_CTRL, 0);
    }
    loop {
        core::hint::spin_loop();
    }
}
