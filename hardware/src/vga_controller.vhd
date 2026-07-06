library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.palette;

entity vga_controller is
  port (
    -- System Signals (For CPU MMIO Interface)
    clk          : in    std_logic;
    system_reset : in    std_logic;

    -- XBUS / Wishbone Target Interface
    wb_adr_i     : in    std_logic_vector(31 downto 0);
    wb_dat_i     : in    std_logic_vector(31 downto 0);
    wb_dat_o     : out   std_logic_vector(31 downto 0);
    wb_we_i      : in    std_logic;
    wb_sel_i     : in    std_logic_vector(3 downto 0);
    wb_stb_i     : in    std_logic;
    wb_cyc_i     : in    std_logic;
    wb_ack_o     : out   std_logic;

    -- Video Pipeline Clock
    pixel_clock  : in    std_logic;
    
    -- Interrupt output to CPU
    irq_vblank   : out   std_logic;

    -- Physical VGA Output Pins
    vga_red      : out   std_logic_vector(3 downto 0);
    vga_green    : out   std_logic_vector(3 downto 0);
    vga_blue     : out   std_logic_vector(3 downto 0);
    h_sync       : out   std_logic;
    v_sync       : out   std_logic
  );
end entity vga_controller;

architecture behavioral of vga_controller is

  -- Internal Timing Counters
  signal h_cnt   : integer range 0 to 799 := 0;
  signal v_cnt   : integer range 0 to 524 := 0;
  signal hsync_i : std_logic;
  signal vsync_i : std_logic;
  signal blank_i : std_logic;

  -- Video Pipeline Color Drivers
  signal color     : std_logic_vector(11 downto 0) := (others => '0');
  signal hsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal vsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal blank_reg : std_logic_vector(3 downto 0)  := (others => '0');
  signal vga_out   : std_logic_vector(11 downto 0);
  
  -- Interrupt Tracker
  signal irq_vblank_i : std_logic := '0';

  -- Memory Mapped Register (Holds 12-bit RGB color: Bits 11:8 R, 7:4 G, 3:0 B)
  signal bg_color_reg : std_logic_vector(11 downto 0) := (others => '0');

  -- Neue Register hinzufügen für Position
  signal player_x_reg : unsigned(31 downto 0) := to_unsigned(100, 32);
  signal player_y_reg : unsigned(31 downto 0) := to_unsigned(370, 32);

  constant PLAYER_SIZE : integer := 30;
  constant GROUND_Y    : integer := 400;

begin

  -- Drive the physical interrupt output pin
  irq_vblank <= irq_vblank_i;

  -- =========================================================================
  -- CPU MMIO Interface (Wishbone Protocol)
  -- anhängig von der Adresse 
  -- =========================================================================
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      player_x_reg <= to_unsigned(100, 32);
      player_y_reg <= to_unsigned(370, 32);
      bg_color_reg <= x"BCF";
      wb_ack_o     <= '0';

    elsif rising_edge(clk) then
      wb_ack_o <= '0';

      if (wb_cyc_i = '1' and wb_stb_i = '1') then
        wb_ack_o <= '1';

        if wb_we_i = '1' then
          case wb_adr_i(5 downto 2) is

            -- 0x1000_0000
            when "0000" =>
              player_x_reg <= unsigned(wb_dat_i);

            -- 0x1000_0004
            when "0001" =>
              player_y_reg <= unsigned(wb_dat_i);

            -- 0x1000_0008
            when "0010" =>
              bg_color_reg <= wb_dat_i(11 downto 0);

            when others =>
              null;

          end case;
        end if;
      end if;
    end if;
  end process;

    -- Leseprozess, CPU bekommt je nach Adresse den passenden Wert zurück
    process (all) is
    begin
      case wb_adr_i(5 downto 2) is

        when "0000" =>
          wb_dat_o <= std_logic_vector(player_x_reg);

        when "0001" =>
          wb_dat_o <= std_logic_vector(player_y_reg);

        when "0010" =>
          wb_dat_o <= x"00000" & bg_color_reg;

        when others =>
          wb_dat_o <= (others => '0');

      end case;
    end process;

  -- =========================================================================
  -- Video Timing and Rendering Engine (Pixel Clock Domain)
  -- =========================================================================
  
  -- Drive color from the MMIO register
    process (all) is
    variable sx : integer;
    variable sy : integer;
    variable px : integer;
    variable py : integer;
  begin
    color <= bg_color_reg;

    px := to_integer(player_x_reg(9 downto 0));
    py := to_integer(player_y_reg(9 downto 0));

    -- active screen area in his VGA timing:
    -- h_cnt 144..783 => x 0..639
    -- v_cnt 35..514  => y 0..479
    if (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) then

      sx := h_cnt - 144;
      sy := v_cnt - 35;

      -- background
      color <= bg_color_reg;

      -- ground
      if sy >= GROUND_Y then
        color <= x"666";
      end if;

      -- player cube
      if (sx >= px and sx < px + PLAYER_SIZE and
          sy >= py and sy < py + PLAYER_SIZE) then
        color <= x"0FF";
      end if;

    else
      color <= x"000";
    end if;
  end process;

  -- Generate structural timing Sync Assertions
  hsync_i <= '0' when (h_cnt < 96) else '1';
  vsync_i <= '0' when (v_cnt < 2)  else '1';
  
  -- Active display area: H(144 to 783), V(35 to 514)
  blank_i <= '0' when (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) else '1';

  -- Sync Generation and Interrupt Logic
  process (pixel_clock, system_reset) is
  begin
    if system_reset = '1' then
      h_cnt        <= 0;
      v_cnt        <= 0;
      irq_vblank_i <= '0';
    elsif rising_edge(pixel_clock) then
      
      -- Default interrupt pulse low
      irq_vblank_i <= '0';

      if (h_cnt = 799) then
        h_cnt   <= 0;

        if (v_cnt = 524) then
          v_cnt <= 0;
        else
          v_cnt <= v_cnt + 1;
          
          -- V-Blank begins the moment we leave the active vertical area (line 515)
          if (v_cnt = 514) then
            irq_vblank_i <= '1'; -- Stays high for exactly 1 pixel clock cycle
          end if;
        end if;
      else
        h_cnt <= h_cnt + 1;
      end if;

    end if;
  end process;

  -- 4-Stage Pipeline Latency Delay for VGA alignment
  process (pixel_clock) is
  begin
    if rising_edge(pixel_clock) then
      hsync_reg <= hsync_reg(2 downto 0) & hsync_i;
      vsync_reg <= vsync_reg(2 downto 0) & vsync_i;
      blank_reg <= blank_reg(2 downto 0) & blank_i;
    end if;
  end process;

  -- Display Blanking Multi-plexer
  process (color, blank_reg) is
  begin
    if (blank_reg(3) = '1') then
      vga_out <= (others => '0');
    else
      vga_out <= color; 
    end if;
  end process;

  -- Assign Physical Output Pins
  vga_red   <= vga_out(11 downto 8);
  vga_green <= vga_out(7 downto 4);
  vga_blue  <= vga_out(3 downto 0);
  h_sync    <= hsync_reg(3);
  v_sync    <= vsync_reg(3);

end architecture behavioral;
