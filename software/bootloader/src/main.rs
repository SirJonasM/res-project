#![no_std]
#![no_main]
#![feature(abi_riscv_interrupt)]
use core::arch::global_asm;
use pac::println;
use pac::leds::set_leds;
use pac::uart::read_char;
use pac::uart::uart_putchar;
use pac::wdt::watchdog_feed;
use pac::wdt::watchdog_init;
use riscv::register::mstatus;
use riscv::register::mtvec;

pub extern crate panic_bootloader;

global_asm!(include_str!("start.S"));

// Constants for our protocol
// System Status Codes (LEDs 0-1)
const LED_STATUS_IDLE: u32 = 0x01; // LED 0 on: Bootloader waiting
const LED_STATUS_LOADING: u32 = 0x02; // LED 1 on: Actively receiving data

// Error Codes (LEDs 8-11)
const ERR_OVERFLOW: u32 = 0x100; // LED 8 on: App binary is too large (>12KB)
const ERR_BAD_CHECKSUM: u32 = 0x200; // LED 9 on: Checksum mismatch
const ERR_UNKNOWN_CMD: u32 = 0x400; // LED 10 on: Unknown protocol command

const APP_START_ADDRESS: *mut u8 = 0x0000_1000 as *mut u8;
const MAX_APP_SIZE: usize = 28 * 1024; // 12 KB

// Protocol Constants
const SYNC_BYTE: u8 = 0xAA;
const CMD_WRITE_CHUNK: u8 = 0x01;
const CMD_BOOT: u8 = 0x02;
const CMD_RESET: u8 = 0x03;
const ACK: u8 = 0x06;
const NACK: u8 = 0x15;

/// Blocks until a single character is safely received over UART.
fn blocking_read_char() -> u8 {
    loop {
        if let Some(c) = read_char() {
            return c;
        }
        watchdog_feed();
    }
}

// --- Main Bootloader Loop ---
// Define your FPGA's clock frequency here (e.g., 50 MHz)
const CLOCK_FREQUENCY_HZ: u32 = 100_000_000;
// Calculate the 5-second timeout register value automatically
const WDT_TIMEOUT_5_SECONDS: u32 = (5 * CLOCK_FREQUENCY_HZ) / 4096;
#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    println!("------This is the Bootloader-------");
    unsafe {
        mtvec::write(mtvec::Mtvec::new(
            trap_handler as *const () as usize,
            mtvec::TrapMode::Direct,
        ));

        // 3. Enable Global Interrupts (MIE bit in mstatus)
        mstatus::set_mie();
    }
    set_leds(LED_STATUS_IDLE);
    watchdog_init(WDT_TIMEOUT_5_SECONDS);

    loop {
        // 1. Synchronize to Packet Start
        if blocking_read_char() != SYNC_BYTE {
            continue;
        }

        // We found a packet, update LEDs to show active loading state
        set_leds(LED_STATUS_LOADING);

        // 2. Read the Header
        let cmd = blocking_read_char();
        let len = ((blocking_read_char() as usize) << 8) | (blocking_read_char() as usize);
        let offset = ((blocking_read_char() as usize) << 8) | (blocking_read_char() as usize);

        // Compute base header checksum
        let mut calculated_checksum =
            cmd ^ ((len >> 8) as u8) ^ (len as u8) ^ ((offset >> 8) as u8) ^ (offset as u8);

        // 3. Command Multiplexing with Error Handling
        match cmd {
            CMD_WRITE_CHUNK => {
                // Error Handle: Size verification
                if offset + len > MAX_APP_SIZE {
                    set_leds(LED_STATUS_IDLE | ERR_OVERFLOW);
                    uart_putchar(NACK);
                    continue;
                }

                // Gather payload stream directly into RAM
                for i in 0..len {
                    let byte = blocking_read_char();
                    calculated_checksum ^= byte;

                    unsafe {
                        let target_ptr = APP_START_ADDRESS.add(offset + i);
                        core::ptr::write_volatile(target_ptr, byte);
                    }
                }

                // Verify Checksum
                let received_checksum = blocking_read_char();
                if calculated_checksum == received_checksum {
                    uart_putchar(ACK);
                    // Clear out error visual flags upon a successful chunk write
                    set_leds(LED_STATUS_LOADING);
                } else {
                    set_leds(LED_STATUS_LOADING | ERR_BAD_CHECKSUM);
                    uart_putchar(NACK);
                }
            }

            CMD_BOOT => {
                let received_checksum = blocking_read_char();
                if calculated_checksum == received_checksum {
                    uart_putchar(ACK);

                    // Clear LEDs before launching app so app can use them fresh
                    set_leds(0);
                    println!("Jumping to main.");

                    // Execute Jump
                    // Clear out the instruction cache before jumping to new code!
                    unsafe {
                        core::arch::asm!("fence.i");

                        // Explicitly target the correct application address
                        let app_entry = APP_START_ADDRESS as *const ();
                        let rename_fn: extern "C" fn() -> ! = core::mem::transmute(app_entry);

                        rename_fn();
                    }
                } else {
                    set_leds(LED_STATUS_IDLE | ERR_BAD_CHECKSUM);
                    uart_putchar(NACK);
                }
            }

            CMD_RESET => {
                // Software jump back to 0x0000_0000 or your hardware reset bit
                #[allow(clippy::zero_ptr)]
                unsafe {
                    let boot_entry = 0x0000_0000 as *const extern "C" fn() -> !;
                    (*boot_entry)();
                }
            }

            _ => {
                // Error Handle: Received an invalid command ID
                set_leds(LED_STATUS_IDLE | ERR_UNKNOWN_CMD);
                uart_putchar(NACK);
            }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "riscv-interrupt-m" fn trap_handler() {
    panic!()
}
