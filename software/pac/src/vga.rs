use core::ptr::read_volatile;

const GAME_BASE: usize = 0x1000_0000;

const REG_PLAYER_X: *const u32 = GAME_BASE as *const u32;            // 0x00
const REG_PLAYER_Y: *const u32 = (GAME_BASE + 0x04) as *const u32;   // 0x04
const REG_BG_COLOR: *const u32 = (GAME_BASE + 0x08) as *const u32;   // 0x08
const REG_STATE:    *const u32 = (GAME_BASE + 0x10) as *const u32;   // 0x10 (Game Over flag)
const REG_SCORE:    *const u32 = (GAME_BASE + 0x14) as *const u32;   // 0x14
const REG_SPEED:    *const u32 = (GAME_BASE + 0x18) as *const u32;   // 0x18

/// Represents the status returned by the hardware state register.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum GameState {
    Active   = 0x0,
    GameOver = 0x1,
}

impl From<u32> for GameState {
    fn from(val: u32) -> Self {
        if (val & 0x1) == 1 {
            GameState::GameOver
        } else {
            GameState::Active
        }
    }
}

pub struct GameDriver;

impl GameDriver {
    /// Reads the player's current X coordinate.
    pub fn read_player_x() -> u32 {
        unsafe { read_volatile(REG_PLAYER_X) }
    }

    /// Reads the player's current Y coordinate.
    pub fn read_player_y() -> u32 {
        unsafe { read_volatile(REG_PLAYER_Y) }
    }

    /// Reads the background color (12-bit RGB value: Bits 11:8 R, 7:4 G, 3:0 B).
    pub fn read_bg_color() -> u16 {
        unsafe { (read_volatile(REG_BG_COLOR) & 0x0FFF) as u16 }
    }

    /// Reads the current game state (Active vs GameOver flag from VHDL).
    pub fn read_game_state() -> GameState {
        let raw_state = unsafe { read_volatile(REG_STATE) };
        GameState::from(raw_state)
    }

    /// Reads the current game score.
    pub fn read_score() -> u32 {
        unsafe { read_volatile(REG_SCORE) }
    }

    /// Reads the current game speed setting.
    pub fn read_speed() -> u32 {
        unsafe { read_volatile(REG_SPEED) }
    }
}
