use core::ptr::{read_volatile, write_volatile};

const PLAYER_X: *mut u32 = 0x1000_0000 as *mut u32;
const PLAYER_Y: *mut u32 = 0x1000_0004 as *mut u32;
const BG_COLOR: *mut u32 = 0x1000_0008 as *mut u32;
const CONTROL: *mut u32 = 0x1000_0010 as *mut u32;
const SCORE: *const u32 = 0x1000_0014 as *const u32;
const SPEED: *mut u32 = 0x1000_0018 as *mut u32;


/// Sets player x-position
pub fn set_player_x(x: u32) {
    unsafe {
        write_volatile(PLAYER_X, x);
    }
}

/// Sets player y-position
pub fn set_player_y(y: u32) {
    unsafe {
        write_volatile(PLAYER_Y, y);
    }
}

/// Sets both player coordinates
pub fn set_player_pos(x: u32, y: u32) {
    set_player_x(x);
    set_player_y(y);
}

/// Sets background color using 4-bit RGB values
pub fn set_bg_color(r: u8, g: u8, b: u8) {
    let color =
        (((r & 0xF) as u32) << 8) |
        (((g & 0xF) as u32) << 4) |
        ((b & 0xF) as u32);

    unsafe {
        write_volatile(BG_COLOR, color);
    }
}

/// Reads player x-position
pub fn read_player_x() -> u32 {
    unsafe {
        read_volatile(PLAYER_X)
    }
}

/// Reads player y-position
pub fn read_player_y() -> u32 {
    unsafe {
        read_volatile(PLAYER_Y)
    }
}

/// Reads current background color
pub fn read_bg_color() -> (u8, u8, u8) {
    let raw_color = unsafe {
        read_volatile(BG_COLOR)
    };

    let r = ((raw_color >> 8) & 0xF) as u8;
    let g = ((raw_color >> 4) & 0xF) as u8;
    let b = (raw_color & 0xF) as u8;

    (r, g, b)
}

/// reset
pub fn reset_game() {
    unsafe {
        write_volatile(CONTROL, 1);
    }
}

pub fn read_game_over() -> bool {
    unsafe {
        (read_volatile(CONTROL) & 1) != 0
    }
}

pub fn read_score() -> u32 {
    unsafe {
        read_volatile(SCORE)
    }
}


pub fn set_game_speed(speed: u32) {
    unsafe {
        write_volatile(SPEED, speed);
    }
}