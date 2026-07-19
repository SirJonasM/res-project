use core::ptr::{read_volatile, write_volatile};

// Base address derived from your code comments (e.g., 0x1000_0008 was offset 0x08)
const GAME_BASE: usize = 0x1000_0000;

// Register offsets (wb_adr_i(5 downto 2) mapped to byte offsets)
const REG_PLAYER_X: *mut u32 = GAME_BASE as *mut u32; // "0000"
const REG_PLAYER_Y: *mut u32 = (GAME_BASE + 0x04) as *mut u32; // "0001"
const REG_BG_COLOR: *mut u32 = (GAME_BASE + 0x08) as *mut u32; // "0010"
const REG_STATE:    *mut u32 = (GAME_BASE + 0x10) as *mut u32; // "0100" (Read: State, Write: Reset)
const REG_SCORE:    *mut u32 = (GAME_BASE + 0x14) as *mut u32; // "0101"
const REG_SPEED:    *mut u32 = (GAME_BASE + 0x18) as *mut u32; // "0110"

/// Represents the game state, decoded from your VHDL one-hot representation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum GameState {
    Menu         = 0x01, // "0001"
    Running      = 0x02, // "0010"
    Paused       = 0x04, // "0100"
    GameOver     = 0x08, // "1000"
    Unknown      = 0x00,
}

impl From<u32> for GameState {
    fn from(val: u32) -> Self {
        match val & 0xF {
            0x01 => GameState::Menu,
            0x02 => GameState::Running,
            0x04 => GameState::Paused,
            0x08 => GameState::GameOver,
            _    => GameState::Unknown,
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

    /// Reads the background color (masked to 12 bits as per VHDL mapping).
    pub fn read_bg_color() -> u16 {
        unsafe { (read_volatile(REG_BG_COLOR) & 0x0FFF) as u16 }
    }

    /// Writes a new 12-bit background color.
    pub fn write_bg_color(color: u16) {
        let masked_color = (color & 0x0FFF) as u32;
        unsafe { write_volatile(REG_BG_COLOR, masked_color); }
    }

    /// Reads the current one-hot encoded game state.
    pub fn read_game_state() -> GameState {
        let raw_state = unsafe { read_volatile(REG_STATE) };
        GameState::from(raw_state)
    }

    /// Triggers a game reset sequence by writing a '1' to bit 0 of the control/state register.
    pub fn reset_game() {
        unsafe { write_volatile(REG_STATE, 0x1); }
    }

    /// Reads the current game score.
    pub fn read_score() -> u32 {
        unsafe { read_volatile(REG_SCORE) }
    }

    /// Reads the current game speed setting.
    pub fn read_speed() -> u32 {
        unsafe { read_volatile(REG_SPEED) }
    }

    /// Sets the game speed. 
    /// Note: Your VHDL clamps values automatically (under 3 becomes 3, over 4 becomes 4).
    pub fn write_speed(speed: u8) {
        let val = (speed & 0x0F) as u32;
        unsafe { write_volatile(REG_SPEED, val); }
    }
}
