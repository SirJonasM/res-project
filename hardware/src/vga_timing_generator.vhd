library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity vga_timing_generator is
  port (
    clk          : in    std_logic;
    system_reset : in    std_logic;
    pixel_clock  : in    std_logic;
    h_cnt        : out   integer range 0 to 799;
    v_cnt        : out   integer range 0 to 524;
    hsync_raw    : out   std_logic;
    vsync_raw    : out   std_logic;
    blank_raw    : out   std_logic;
    vblank_pix   : out   std_logic
  );
end entity vga_timing_generator;

architecture behavioral of vga_timing_generator is
  signal h_cnt_i   : integer range 0 to 799 := 0;
  signal v_cnt_i   : integer range 0 to 524 := 0;
begin
  h_cnt <= h_cnt_i;
  v_cnt <= v_cnt_i;

  -- Raw timing combinations
  hsync_raw <= '0' when (h_cnt_i < 96) else '1';
  vsync_raw <= '0' when (v_cnt_i < 2)  else '1';
  blank_raw <= '0' when (h_cnt_i >= 144 and h_cnt_i < 784 and v_cnt_i >= 35 and v_cnt_i < 515) else '1';

  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      h_cnt_i    <= 0;
      v_cnt_i    <= 0;
      vblank_pix <= '0';
    elsif rising_edge(clk) then
      if pixel_clock = '1' then
        -- Counter Advancements
        if (h_cnt_i = 799) then
          h_cnt_i <= 0;
          if (v_cnt_i = 524) then
            v_cnt_i <= 0;
          else
            v_cnt_i <= v_cnt_i + 1;
          end if;
        else
          h_cnt_i <= h_cnt_i + 1;
        end if;

        -- VBlank detection pulse
        if v_cnt_i >= 515 then
          vblank_pix <= '1';
        else
          vblank_pix <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture behavioral;
