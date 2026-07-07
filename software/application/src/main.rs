#![no_std]
#![no_main]
#![feature(abi_riscv_interrupt)]
pub extern crate panic_application;

mod interrupts;

use core::arch::global_asm;
use pac::println;
use pac::vga::{set_bg_color, set_player_pos, set_player_y, reset_game, read_game_over}; 

use crate::interrupts::setup_interrupts;

global_asm!(include_str!("start.S"));

use core::cell::UnsafeCell;

// --- Your original clean EventQueue implementation ---
pub const QUEUE_SIZE: usize = 16;

#[derive(Copy, Clone, Debug, PartialEq)]
pub enum GameEvent {
    VBlank,
    ButtonJump,
    LevelStart,
    PlayerDeath,
}

pub struct EventQueue {
    buffer: [GameEvent; QUEUE_SIZE],
    head: usize,
    tail: usize,
}

impl EventQueue {
    pub const fn new() -> Self {
        Self {
            buffer: [GameEvent::VBlank; QUEUE_SIZE],
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

enum Speed {
    Low,
    Middle,
    Fast,
    VeryFast,
}

struct App {
    time_step: usize,
    player: Player,
    speed: Speed,
}

struct Player {
    y: i32,
    velocity_y: i32,
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    println!("Hello World");
    // setup_interrupts();

    set_bg_color(0xB, 0xC, 0xF);
    set_player_pos(100, 370);
    reset_game();

    let mut app = App {
        player: Player {
            y: 370,
            velocity_y: 0,
        },
        time_step: 0,
        speed: Speed::Low,
    };

    /*loop {
        let event = GAME_QUEUE.lock(|queue| queue.pop());
        match event {
            Some(GameEvent::VBlank) => app.next_frame(),
            Some(GameEvent::ButtonJump) => app.player_jump(),
            Some(GameEvent::LevelStart) => app.start_level(),
            Some(GameEvent::PlayerDeath) => app.player_died(),
            None => {}
        };
        pac::wdt::watchdog_feed();
    } */

    loop {
    if read_game_over() {
        println!("Game Over");

        for _ in 0..20_000_000 {
            core::hint::spin_loop();
            pac::wdt::watchdog_feed();
        }

        reset_game();
    }

    pac::wdt::watchdog_feed();
    }
    let mut y: i32 = 370;
    let mut dir: i32 = -1;

   /* loop {
    set_player_y(y as u32);

    y += dir;

    if y <= 250 {
        dir = 1;
    }

    if y >= 370 {
        dir = -1;
    }

    for _ in 0..300_000 {
        core::hint::spin_loop();
    }

    pac::wdt::watchdog_feed();
}*/
}

impl Player {
    pub fn move_player(&mut self) {
        const GROUND_Y: i32 = 370;
        const GRAVITY: i32 = 1;

        self.velocity_y += GRAVITY;
        self.y += self.velocity_y;

        if self.y > GROUND_Y {
            self.y = GROUND_Y;
            self.velocity_y = 0;
        }

        if self.y < 0 {
            self.y = 0;
            self.velocity_y = 0;
        }
    }

    pub fn jump(&mut self) {
        const GROUND_Y: i32 = 370;

        if self.y == GROUND_Y {
            self.velocity_y = -12;
        }
    }
}

impl App {
    fn next_frame(&mut self) {
        self.player.move_player();
        set_player_y(self.player.y as u32);
    }

    fn player_jump(&mut self) {
        println!("Player jumped");
        self.player.jump();
    }

    fn start_level(&mut self) {}

    fn player_died(&mut self) {}
}