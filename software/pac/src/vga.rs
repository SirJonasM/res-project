use core::ptr::read_volatile;

const GAME_BASE: usize = 0x1000_0000;

const REG_PLAYER_X: *const u32 = GAME_BASE as *const u32;            // 0x00
const REG_PLAYER_Y: *const u32 = (GAME_BASE + 0x04) as *const u32;   // 0x04
const REG_BG_COLOR: *const u32 = (GAME_BASE + 0x08) as *const u32;   // 0x08
const REG_STATE:    *const u32 = (GAME_BASE + 0x10) as *const u32;   // 0x10 (Game Over flag)
const REG_SCORE:    *const u32 = (GAME_BASE + 0x14) as *const u32;   // 0x14
const REG_SPEED:    *const u32 = (GAME_BASE + 0x18) as *const u32;   // 0x18

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GameState {
    Menu,
    Running,
    Paused,
    GameOver,
    Invalid(u32),
}

impl From<u32> for GameState {
    fn from(value: u32) -> Self {
        match value & 0x0F {
            0x01 => GameState::Menu,
            0x02 => GameState::Running,
            0x04 => GameState::Paused,
            0x08 => GameState::GameOver,
            other => GameState::Invalid(other),
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
