use pac::{print, uart::read_char};
use riscv::register::{mie, mstatus, mtvec};

pub fn setup_interrupts() {
    unsafe {
        mtvec::write(mtvec::Mtvec::new(
            trap_handler as *const () as usize,
            mtvec::TrapMode::Direct,
        ));

        mie::set_mext();

        mstatus::set_mie();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "riscv-interrupt-m" fn trap_handler() {
    let mcause = riscv::register::mcause::read();

    if mcause.is_interrupt() {
        if mcause.code() == 11 {
            unsafe {
                handle_external_interrupts();
            }
        }
    } else {
        panic!()
    }
}

const IRQ_STATUS_REG: *mut u32 = 0x8000_0000 as *mut u32;
const IRQ_MASK_BTNC: u32 = 1;
const IRQ_MASK_UART: u32 = 2;
const IRQ_MASK_VGA: u32 = 4;

unsafe fn handle_external_interrupts() {
    let status = unsafe { core::ptr::read_volatile(IRQ_STATUS_REG) };
    if (status & IRQ_MASK_BTNC) != 0 {
        let event = GameEvent::ButtonJump;
        GAME_QUEUE.lock(|queue| queue.push(event)).unwrap();
    }
    if (status & IRQ_MASK_UART) != 0
        && let Some(c) = read_char()
    {
        print!("{}", c as char);
    }
    if (status & IRQ_MASK_VGA) != 0 {
        let event = GameEvent::VBlank;
        GAME_QUEUE.lock(|queue| queue.push(event)).unwrap();
    }
}
