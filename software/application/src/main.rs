#![no_std]
#![no_main]
#![feature(abi_riscv_interrupt)]

use core::arch::global_asm;
use pac::print;
use pac::println;
use pac::uart::read_char;
use riscv::register::{mie, mstatus, mtvec};

global_asm!(include_str!("start.S"));

#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    unsafe {
        // 1. Register the trap handler address into mtvec
        // We set Direct Mode (00), meaning all traps jump to this single function
        mtvec::write(mtvec::Mtvec::new(
            trap_handler as *const () as usize,
            mtvec::TrapMode::Direct,
        ));

        // 2. Enable Machine External Interrupts specifically (MEIE bit in mie)
        mie::set_mext();

        // 3. Enable Global Interrupts (MIE bit in mstatus)
        mstatus::set_mie();

        // Main background application loop
        println!("Hello World");
        loop {
            pac::wdt::watchdog_feed();
        }
    }
}

/// The Global Trap Vector
/// RISC-V expects this function to handle traps.
/// Ensure it uses the "riscv-interrupt-m" ABI so the compiler generates
/// the proper context saving/restoring (mret) instructions.
#[unsafe(no_mangle)]
pub unsafe extern "riscv-interrupt-m" fn trap_handler() {
    let mcause = riscv::register::mcause::read();

    // Check if the trap was caused by an Interrupt (high bit set)
    if mcause.is_interrupt() {
        if mcause.code() == 11 {
            // 11 = Machine External Interrupt (mext_irq_i)
            unsafe {
                handle_external_interrupts();
            }
        }
    } else {
        // Handle synchronous exceptions (illegal instruction, load faults, etc.)
        panic!()
    }
}

// Replace this with your exact decoded address (assuming 0x80000000)
const IRQ_STATUS_REG: *mut u32 = 0x8000_0000 as *mut u32;
const IRQ_MASK_BTNC: u32 = 1;
const IRQ_MASK_UART: u32 = 2;

unsafe fn handle_external_interrupts() {
    let status = unsafe { core::ptr::read_volatile(IRQ_STATUS_REG) };
    if (status & IRQ_MASK_BTNC) != 0 {
        println!("Button Interrupt");
    }
    if (status & IRQ_MASK_UART) != 0
        && let Some(c) = read_char()
    {
        print!("{c}");
    }
}
