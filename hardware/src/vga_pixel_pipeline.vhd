library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.game_pkg.all;

entity vga_pixel_pipeline is
  port (
    clk             : in    std_logic;
    pixel_clock     : in    std_logic;
    
    -- Beam Coordinate Inputs
    h_cnt           : in    integer range 0 to 799;
    v_cnt           : in    integer range 0 to 524;
    hsync_raw       : in    std_logic;
    vsync_raw       : in    std_logic;
    blank_raw       : in    std_logic;

    -- Global Constants & Configuration States
    player_x        : in    unsigned(31 downto 0);
    player_y        : in    unsigned(31 downto 0);
    camera_x        : in    integer range 0 to 16000;
    camera_progress : in    integer;
    game_state_out  : in    std_logic_vector(1 downto 0);
    speed_reg       : in    integer range 3 to 4;
    game_over       : in    std_logic;
    bg_color_reg    : in    std_logic_vector(11 downto 0);

    -- Driver Interconnect Outputs out to Physical DAC Layer
    vga_red         : out   std_logic_vector(3 downto 0);
    vga_green       : out   std_logic_vector(3 downto 0);
    vga_blue        : out   std_logic_vector(3 downto 0);
    h_sync          : out   std_logic;
    v_sync          : out   std_logic
  );
end entity vga_pixel_pipeline;

architecture behavioral of vga_pixel_pipeline is
  -- Core Engine Stage Variables
  signal r1_active, r2_active, r2_map_valid : std_logic := '0';
  signal r1_sx, r1_sy, r1_world_x           : integer := 0;
  signal r2_sx, r2_sy, r2_tile_col, r2_tile_row, r2_local_x, r2_local_y : integer := 0;
  signal r1_progress_w, r2_progress_w       : integer := 0;

  signal color     : std_logic_vector(11 downto 0) := (others => '0');
  signal hsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal vsync_reg : std_logic_vector(3 downto 0)  := (others => '1');
  signal blank_reg : std_logic_vector(3 downto 0)  := (others => '0');

  type color_pipe_t is array (0 to 3) of std_logic_vector(11 downto 0);
  signal color_pipe    : color_pipe_t := (others => (others => '0'));
  signal color_delayed : std_logic_vector(11 downto 0);

  constant PLAYER_SIZE  : integer := 30;
  constant GROUND_Y     : integer := 400;
  constant MAP_START_X  : integer := 640;
  constant TILE_SIZE    : integer := 30;
  constant TILE_STEP    : integer := 32;
  constant LEVEL_END_X  : integer := MAP_START_X + MAP_COLS * TILE_STEP;
  constant SPIKE_WIDTH  : integer := 20;
  constant SPIKE_HEIGHT : integer := 30;

begin

  -- Math Pipeline Engine (Zero Div/Mod Hardware Structure)
  vga_math_pipeline_proc : process(clk) is
    variable px_i, py_i, tile_index, tile_val, v_offset, div_row, rem_row : integer;
    variable world_offset : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      if pixel_clock = '1' then
        
        -- STAGE 1: Fast Bounds Truncation
        if (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) then
          r1_active  <= '1';
          r1_sx      <= h_cnt - 144;
          r1_sy      <= v_cnt - 35;
          r1_world_x <= (h_cnt - 144) + camera_x;
        else
          r1_active  <= '0'; r1_sx <= 0; r1_sy <= 0; r1_world_x <= 0;
        end if;
        r1_progress_w <= camera_progress;

        -- STAGE 2: Optimized Bit-Shift Calculations
        r2_active     <= r1_active;
        r2_sx         <= r1_sx;
        r2_sy         <= r1_sy;
        r2_progress_w <= r1_progress_w;

        if r1_world_x >= MAP_START_X and r1_world_x < LEVEL_END_X and r1_sy >= 310 and r1_sy < 400 then
          r2_map_valid <= '1';
          world_offset := to_unsigned(r1_world_x - MAP_START_X, 32);
          r2_tile_col  <= to_integer(shift_right(world_offset, 5));
          r2_local_x   <= to_integer(world_offset(4 downto 0));
          
          v_offset := r1_sy - 310;
          if v_offset < 30 then div_row := 0; elsif v_offset < 60 then div_row := 1; else div_row := 2; end if;
          r2_tile_row <= div_row;

          rem_row := v_offset - (to_integer(shift_left(to_unsigned(div_row, 8), 5)) - to_integer(shift_left(to_unsigned(div_row, 8), 1)));
          r2_local_y <= rem_row;
        else
          r2_map_valid <= '0'; r2_tile_col <= 0; r2_tile_row <= 0; r2_local_x <= 0; r2_local_y <= 0;
        end if;

        -- STAGE 3: Map Lookup & Color Assignment Matrix
        px_i := to_integer(player_x(9 downto 0));
        py_i := to_integer(player_y(9 downto 0));

        if r2_active = '1' then
          color <= bg_color_reg;

          if r2_sy >= GROUND_Y then
            color <= x"014";
          end if;

          if r2_map_valid = '1' then
            tile_index := r2_tile_row * MAP_COLS + r2_tile_col;
            tile_val   := LEVEL_MAP(tile_index);

            if tile_val = TILE_BLOCK then
              color <= x"FF0";
            elsif tile_val = TILE_SPIKE then
              if r2_local_x < SPIKE_WIDTH and r2_local_y < SPIKE_HEIGHT then
                if (r2_local_y >= SPIKE_HEIGHT - r2_local_x and r2_local_x < SPIKE_WIDTH / 2) or
                   (r2_local_y >= SPIKE_HEIGHT - ((SPIKE_WIDTH - 1) - r2_local_x) and r2_local_x >= SPIKE_WIDTH / 2) then
                  color <= x"F00";
                end if;
              end if;
            end if;
          end if;

          -- Rendering UI & HUD elements
          if (r2_sy >= 10 and r2_sy < 18) then
            if (r2_sx >= 20 and r2_sx < 620) then
              color <= x"0F0" when (r2_sx < 20 + r2_progress_w) else x"333";
            end if;
          end if;

          if (r2_sx >= px_i and r2_sx < px_i + PLAYER_SIZE and r2_sy >= py_i and r2_sy < py_i + PLAYER_SIZE) then
            color <= x"F00" when game_over = '1' else x"0F4";
          end if;

          -- Dynamic State Overlays (00=MENU, 10=PAUSED)
          if game_state_out = "00" then
            color <= x"111";
            if r2_sy >= 210 and r2_sy < 230 and r2_sx >= 220 and r2_sx < 300 then
              color <= x"0F0" when (r2_sx < 220 + (speed_reg - 2) * 40) else x"333";
            end if;
            if r2_sx >= 100 and r2_sx < 130 and r2_sy >= 370 and r2_sy < 400 then
              color <= x"0F4";
            end if;
          elsif game_state_out = "10" then
            if (r2_sy >= 20 and r2_sy < 60) then
              if (r2_sx >= 560 and r2_sx < 570) or (r2_sx >= 585 and r2_sx < 595) then
                color <= x"F6C";
              end if;
            end if;
          end if;
        else
          color <= x"000";
        end if;
      end if;
    end if;
  end process;

  -- 4-Stage Synchronous Pipeline Matching Shifts
  process (clk) is
  begin
    if rising_edge(clk) then
      if pixel_clock = '1' then
        hsync_reg <= hsync_reg(2 downto 0) & hsync_raw;
        vsync_reg <= vsync_reg(2 downto 0) & vsync_raw;
        blank_reg <= blank_reg(2 downto 0) & blank_raw;

        color_pipe(0) <= color;
        color_pipe(1) <= color_pipe(0);
        color_pipe(2) <= color_pipe(1);
        color_pipe(3) <= color_pipe(2);
      end if;
    end if;
  end process;

  color_delayed <= color_pipe(3);

  -- Output Output Drivers Interface Stage
  process (clk) is
  begin
    if rising_edge(clk) then
      if pixel_clock = '1' then
        if (blank_reg(3) = '1') then
          vga_red   <= (others => '0');
          vga_green <= (others => '0');
          vga_blue  <= (others => '0');
        else
          vga_red   <= color_delayed(11 downto 8);
          vga_green <= color_delayed(7 downto 4);
          vga_blue  <= color_delayed(3 downto 0);
        end if;
        h_sync <= hsync_reg(3);
        v_sync <= vsync_reg(3);
      end if;
    end if;
  end process;
end architecture behavioral;
