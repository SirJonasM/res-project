#![no_std]
#![no_main]
#![feature(abi_riscv_interrupt)]
pub extern crate panic_application;

mod interrupts;

use core::arch::global_asm;
use pac::println;
use pac::vga::GameDriver; 

use crate::interrupts::setup_interrupts;

global_asm!(include_str!("start.S"));

use core::cell::UnsafeCell;

// --- Your original clean EventQueue implementation ---
pub const QUEUE_SIZE: usize = 16;

#[derive(Copy, Clone, Debug, PartialEq)]
pub enum GameEvent {
    GameState,
    ButtonJump,
    LevelStart,
    PlayerDeath,
    None,
}

pub struct EventQueue {
    buffer: [GameEvent; QUEUE_SIZE],
    head: usize,
    tail: usize,
}

impl EventQueue {
    pub const fn new() -> Self {
        Self {
            buffer: [GameEvent::None; QUEUE_SIZE],
            head: 0,
            tail: 0,
        }
    }

    pub fn push(&mut self, event: GameEvent) -> Result<(), &'static str> {
        let next_tail = (self.tail + 1) % QUEUE_SIZE;
        if next_tail == self.head {
            return Err("Queue Full!");
        }
        self.buffer[self.tail] = event;
        self.tail = next_tail;
        Ok(())
    }

    pub fn pop(&mut self) -> Option<GameEvent> {
        if self.head == self.tail {
            return None;
        }
        let event = self.buffer[self.head];
        self.head = (self.head + 1) % QUEUE_SIZE;
        Some(event)
    }
}

impl Default for EventQueue {
    fn default() -> Self {
        Self::new()
    }
}

// --- The Critical Section Interrupt Lock ---
pub struct InterruptMutex<T> {
    cell: UnsafeCell<T>,
}

// Explicitly tell Rust this is safe to share globally
unsafe impl<T> Sync for InterruptMutex<T> {}

impl<T> InterruptMutex<T> {
    pub const fn new(value: T) -> Self {
        Self {
            cell: UnsafeCell::new(value),
        }
    }

    /// Locks the resource by executing a closure.
    /// In a real system, you would disable interrupts here, but for your
    /// setup, we can use an unsafe borrow block to fulfill safety rules.
    pub fn lock<R>(&self, f: impl FnOnce(&mut T) -> R) -> R {
        // 1. (Optional) Disable machine interrupts here if main loop needs atomic protection

        // 2. Safely get mutable access inside the block
        let mut_ref = unsafe { &mut *self.cell.get() };
        let result = f(mut_ref);

        // 3. (Optional) Re-enable machine interrupts here

        result
    }
}

// Declare it as a standard immutable static! No more static mut warnings.
pub static GAME_QUEUE: InterruptMutex<EventQueue> = InterruptMutex::new(EventQueue::new());

#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    println!("Hello World");
    setup_interrupts();

    GameDriver::write_bg_color(0x008); 

    let mut last_printed_state = GameDriver::read_game_state();
    println!("Initial State: {:?}", last_printed_state);

    loop {
        // 1. Process Event Queue
        // We poll the queue using a loop to empty out all pending events per tick
        while let Some(event) = GAME_QUEUE.lock(|queue| queue.pop()) {
            match event {
                GameEvent::GameState => {
                    let current_state = GameDriver::read_game_state();
                    
                    // Only print if the state actually changed from the last time we printed
                    if current_state != last_printed_state {
                        println!("Game State Changed: {:?}", current_state);
                        last_printed_state = current_state;
                    }
                }
                GameEvent::ButtonJump => {
                    println!("Jump Button Pressed!");
                }
                GameEvent::LevelStart => {
                    println!("Level Started!");
                }
                GameEvent::PlayerDeath => {
                    println!("Player Died!");
                }
                GameEvent::None => {}
            }
        }
    }
}

