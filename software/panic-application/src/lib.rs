#![no_std]

use core::{arch::asm, panic::PanicInfo};
use pac::{println, wdt::trigger_fpga_reset, };
use core::writeln;


#[panic_handler]
pub fn panic(info: &PanicInfo) -> ! {
    let sp: usize;
    let pc: usize;
    unsafe {
        asm!("mv {}, sp", out(reg) sp);
        asm!("auipc {}, 0", out(reg) pc);
    }

    let mcause: usize;
    let mstatus: usize;
    let mtval: usize;
    let mepc: usize;
    unsafe {
        asm!("csrr {}, mcause", out(reg) mcause);
        asm!("csrr {}, mstatus", out(reg) mstatus);
        asm!("csrr {}, mtval", out(reg) mtval);
        asm!("csrr {}, mepc", out(reg) mepc);
    }

        println!("\n!!! APPLICATION PANIC !!!");
        if let Some(location) = info.location() {
            println!("File: {}, Line: {}", location.file(), location.line());
        }
        println!("Message: {}", info.message());

    println!("\n--- Core Register Dump ---");
    println!("PC:       0x{:08X}", pc);
    println!("SP:       0x{:08X}", sp);
    
    println!("\n--- Machine CSR Dump ---");
    println!("MCAUSE:   0x{:08X}", mcause);
    println!("MSTATUS:  0x{:08X}", mstatus);
    println!("MTVAL:    0x{:08X}", mtval);
    println!("MEPC:     0x{:08X}", mepc); 

    trigger_fpga_reset();
}
