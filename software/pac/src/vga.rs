const VGA_BASE: *mut u32 = 0x1000_0000 as *mut u32;

/// Sets the background color using 4-bit RGB values (0 to 15)
pub fn set_vga_color(r: u8, g: u8, b: u8) {
    let color = (((r & 0xF) as u32) << 8) | (((g & 0xF) as u32) << 4) | ((b & 0xF) as u32);
    unsafe {
        core::ptr::write_volatile(VGA_BASE, color);
    }
}

/// Reads the current color and returns it as a tuple: (red, green, blue)
pub fn read_vga_color() -> (u8, u8, u8) {
    let raw_color = unsafe { core::ptr::read_volatile(VGA_BASE) };
    
    let r = ((raw_color >> 8) & 0xF) as u8;
    let g = ((raw_color >> 4) & 0xF) as u8;
    let b = (raw_color & 0xF) as u8;
    
    (r, g, b)
}
