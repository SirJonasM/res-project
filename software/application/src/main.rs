#![no_std]
#![no_main]
pub extern crate panic_application;

use core::arch::global_asm;
use pac::{print, println, uart, wdt::watchdog_feed};

global_asm!(include_str!("start.S"));

use pac::vga::{GameDriver, GameState};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GameSnapshot {
    pub player_x: u32,
    pub player_y: u32,
    pub bg_color: u16,
    pub state: GameState,
    pub score: u32,
    pub speed: u32,
}

impl GameSnapshot {
    /// Reads the current hardware state.
    pub fn read() -> Self {
        Self {
            player_x: GameDriver::read_player_x(),
            player_y: GameDriver::read_player_y(),
            bg_color: GameDriver::read_bg_color(),
            state: GameDriver::read_game_state(),
            score: GameDriver::read_score(),
            speed: GameDriver::read_speed(),
        }
    }

    /// Compares against another snapshot and prints all changes.
    pub fn diff(&self, previous: &Self) {

        if self.bg_color != previous.bg_color {
            println!(
                "bg_color: 0x{:03X} -> 0x{:03X}",
                previous.bg_color, self.bg_color
            );
        }

        if self.state != previous.state {
            println!("state: {:?} -> {:?}", previous.state, self.state);
        }

        if self.score != previous.score {
            println!("score: {} -> {}", previous.score, self.score);
        }

        if self.speed != previous.speed {
            println!("speed: {} -> {}", previous.speed, self.speed);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    let mut previous = GameSnapshot::read();

    loop {
        let current = GameSnapshot::read();

        current.diff(&previous);

        previous = current;

        watchdog_feed();
    }
}
