library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.palette;

entity vga_controller is
  port (
    pixel_clock     : in    std_logic;
    pixel_out       : in    std_logic_vector(5 downto 0);
    bram_addr_b     : out   std_logic_vector(16 downto 0);
    pixel_sub_index : out   integer range 0 to 2;

    -- Physical VGA Output Pins
    vga_red       : out   std_logic_vector(3 downto 0);
    vga_green     : out   std_logic_vector(3 downto 0);
    vga_blue      : out   std_logic_vector(3 downto 0);
    h_sync        : out   std_logic;
    v_sync        : out   std_logic;
    system_reset : in    std_logic
  );
end entity vga_controller;

architecture behavioral of vga_controller is

  -- Internal Timing and Address Counters
  signal h_cnt   : integer range 0 to 799 := 0;
  signal v_cnt   : integer range 0 to 524 := 0;
  signal hsync_i : std_logic;
  signal vsync_i : std_logic;
  signal blank_i : std_logic;

  -- Scaling Trackers
  signal h_scale         : std_logic             := '0';
  signal int_bram_addr_b : unsigned(16 downto 0) := (others => '0');
  signal line_start_addr : unsigned(16 downto 0) := (others => '0');
  signal line_start_sub  : integer range 0 to 2  := 0;
  signal int_sub_index   : integer range 0 to 2  := 0;

  -- Video Pipeline Arrays
  signal color     : std_logic_vector(11 downto 0) := (others => '0');
  signal hsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal vsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal blank_reg : std_logic_vector(3 downto 0)  := (others => '0');
  signal vga_out   : std_logic_vector(11 downto 0);

  signal palette_index : integer range 0 to 63; -- Adjust the range to match your palette size (e.g., 2**pixel_out'length - 1)

begin

  palette_index <= to_integer(unsigned(pixel_out));
  -- Drive external interface assignment updates
  bram_addr_b     <= std_logic_vector(int_bram_addr_b);
  pixel_sub_index <= int_sub_index;

  -- Connect the Palette Component internally
  palette_unit : entity palette
    port map (
      clk   => pixel_clock,
      index => palette_index,
      red   => color(11 downto 8),
      green => color(7 downto 4),
      blue  => color(3 downto 0)
    );

  -- Generate timing Sync Assertions
  hsync_i <= '0' when (h_cnt < 96) else
             '1';
  vsync_i <= '0' when (v_cnt < 2) else
             '1';
  blank_i <= '0' when (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) else
             '1';

  -- Sync Generation and Coordinate Map Process
  process (pixel_clock) is
  begin

    if rising_edge(pixel_clock) then
      if (h_cnt = 799) then
        h_cnt   <= 0;
        h_scale <= '0';

        if (v_cnt = 524) then
          v_cnt           <= 0;
          int_bram_addr_b <= (others => '0');
          line_start_addr <= (others => '0');
          int_sub_index   <= 0;
          line_start_sub  <= 0;
        else
          v_cnt <= v_cnt + 1;

          if (v_cnt >= 35 and v_cnt < 515) then
            if (v_cnt mod 2 /= 0) then
              int_bram_addr_b <= line_start_addr;
              int_sub_index   <= line_start_sub;
            else
              line_start_addr <= int_bram_addr_b;
              line_start_sub  <= int_sub_index;
            end if;
          end if;
        end if;
      else
        h_cnt <= h_cnt + 1;
      end if;

      if (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) then
        h_scale <= not h_scale;

        if (h_scale = '1') then
          if (int_sub_index = 2) then
            int_sub_index   <= 0;
            int_bram_addr_b <= int_bram_addr_b + 1;
          else
            int_sub_index <= int_sub_index + 1;
          end if;
        end if;
      end if;
    end if;

  end process;

  -- 4 Stage Pipeline Latency Register Array
  process (pixel_clock) is
  begin

    if rising_edge(pixel_clock) then
      hsync_reg <= hsync_reg(2 downto 0) & hsync_i;
      vsync_reg <= vsync_reg(2 downto 0) & vsync_i;
      blank_reg <= blank_reg(2 downto 0) & blank_i;
    end if;

  end process;

  -- Blank Display Handling Mux
  process (color, blank_reg) is
  begin

    if (blank_reg(3) = '1') then
      vga_out <= (others => '0');
    else
      vga_out <= color;
    end if;

  end process;

  -- Assign Output Vector Slices
  vga_red   <= vga_out(11 downto 8);
  vga_green <= vga_out(7 downto 4);
  vga_blue  <= vga_out(3 downto 0);
  h_sync    <= hsync_reg(3);
  v_sync    <= vsync_reg(3);

end architecture behavioral;
