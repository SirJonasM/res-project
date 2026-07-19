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
    v_sync       : out   std_logic;

    -- Game input
    btn_menu       : in    std_logic; -- btn_r for speed and pause
    jump_hold_i  : in    std_logic;
    btn_play      : in    std_logic -- btn_c for start und jump
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
  
  -- Interrupt Tracker
  signal irq_vblank_i : std_logic := '0';

  -- Memory Mapped Register (Holds 12-bit RGB color: Bits 11:8 R, 7:4 G, 3:0 B)
  signal bg_color_reg : std_logic_vector(11 downto 0) := x"008";

  -- Neue Register hinzufügen für Position
  signal player_x_reg : unsigned(31 downto 0) := to_unsigned(100, 32);
  signal player_y_reg : unsigned(31 downto 0) := to_unsigned(370, 32);

  constant PLAYER_SIZE : integer := 30;
  constant GROUND_Y    : integer := 400;

  -- RGB, HSync, VSync, blank are properly synchronized with pixel_clock
  type color_pipe_t is array (0 to 3) of std_logic_vector(11 downto 0);
  signal color_pipe    : color_pipe_t := (others => (others => '0'));
  signal color_delayed : std_logic_vector(11 downto 0);

  -- game_tick depends on VGA-VBlank 
  signal game_tick : std_logic := '0';

  signal vblank_pix : std_logic := '0';

  -- Synchronization of pixel_clock to clk
  signal vblank_meta : std_logic := '0';
  signal vblank_sync : std_logic := '0';
  signal vblank_last : std_logic := '0';

  -- jumping cube
  signal velocity_y   : integer range -20 to 20 := 0; -- velocity_y < 0  sprung nach oben
  signal jump_request : std_logic := '0'; -- Buttonpress speichern, weil bei gametick wird vepasst

  constant PLAYER_GROUND_Y : integer := 370;
  constant JUMP_STRENGTH   : integer := -12;
  constant GRAVITY         : integer := 1;

  -- collision / reset
  signal side_collision : std_logic := '0';
  signal game_over : std_logic := '0';
  signal game_reset_req : std_logic := '0';

  --spike
  constant SPIKE_WIDTH  : integer := 20;
  constant SPIKE_HEIGHT : integer := 30;

  signal spike_collision : std_logic := '0';

  -- score
  signal score_reg : unsigned(31 downto 0) := (others => '0');
  signal score_div_counter : integer range 0 to 59 := 0;

  -- speed
  signal speed_reg : integer range 3 to 4 := 3;

  type game_state_t is (MENU, RUNNING, PAUSED, GAME_OVER_STATE);
  signal game_state : game_state_t := MENU;
  signal level_finished_req : std_logic := '0';
  signal reset_delay_counter : integer range 0 to 90 := 0; --

  --tilemap
  constant TILE_EMPTY : integer := 0;
  constant TILE_BLOCK : integer := 1;
  constant TILE_SPIKE : integer := 2;

  constant TILE_SIZE  : integer := 30; 
  constant TILE_STEP  : integer := 32; 
  constant MAP_START_X : integer := 640;

  constant MAP_ROWS : integer := 3;
  constant MAP_COLS : integer := 264;

  -- Tilemap for direct rendering
  type level_map_t is array (0 to (MAP_ROWS * MAP_COLS) - 1) of integer range 0 to 2;   

  constant LEVEL_MAP : level_map_t := (
  -- row 0: top, columns 0?263
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 000-015
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 016-031
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 032-047
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 048-063
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 064-079
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 080-095
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 096-111
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 112-127
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 128-143
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 144-159
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 160-175
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 176-191
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, -- 192-207
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 208-223
  TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 224-239
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 240-255
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 256-263

  -- row 1: middle, columns 0..263
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 000-015
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 016-031
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 032-047
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, -- 048-063
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 064-079
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 080-095
  TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 096-111
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 112-127
  TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 128-143
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, -- 144-159
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, -- 160-175
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 176-191
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 192-207
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 208-223
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 224-239
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 240-255
  TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 256-263

  -- row 2: bottom, columns 0..263
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 000-015
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, -- 016-031
  TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 032-047
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 048-063
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 064-079
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 080-095
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, -- 096-111
  TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, -- 112-127
  TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 128-143
  TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 144-159
  TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 160-175
  TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK ,TILE_BLOCK , TILE_BLOCK, TILE_BLOCK,TILE_BLOCK , TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 176-191
  TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, -- 192-207
  TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, -- 208-223
  TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, -- 224-239
  TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, -- 240-255
  TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK -- 256-263
);


  constant LEVEL_END_X : integer := MAP_START_X + MAP_COLS * TILE_STEP; 
  signal camera_x : integer range 0 to 16000 := 0; -- has to be higher then LEVEL_END_X, depends on map size 


begin

  -- collision check: check only tiles near the player
  collision_proc : process (all) is
    variable px_i           : integer;
    variable py_i           : integer;
    variable player_world_x : integer;
    variable base_col       : integer;
    variable check_col      : integer;
    variable tile_x         : integer;
    variable tile_y         : integer;
    variable side_hit       : std_logic;
    variable spike_hit      : std_logic;
  begin
    px_i := to_integer(player_x_reg(9 downto 0));
    py_i := to_integer(player_y_reg(9 downto 0));

    side_hit  := '0';
    spike_hit := '0';

    -- playerposition + camera-Scroll
    player_world_x := px_i + camera_x; 

    -- calculate the map column where the player is located
    if player_world_x < MAP_START_X then
      base_col := -1;
    else
      base_col := (player_world_x - MAP_START_X) / TILE_STEP;
    end if;

    -- loop only for the the rows
    for row in 0 to MAP_ROWS - 1 loop
      tile_y := PLAYER_GROUND_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;    

      -- only columns near the player: left, center, right
      for col_offset in -1 to 1 loop
        check_col := base_col + col_offset;

        if check_col >= 0 and check_col < MAP_COLS then

          tile_x := MAP_START_X + check_col * TILE_STEP - camera_x;

          if LEVEL_MAP(row * MAP_COLS + check_col) = TILE_BLOCK then

            if (px_i < tile_x + TILE_STEP and -- left edge of player is to the left of right edge of tile 
                px_i + PLAYER_SIZE > tile_x and -- right edge of player is to the right of left edge of tile
                py_i + PLAYER_SIZE > tile_y + 12 and -- bottom edge of player is below top edge of tile
                py_i < tile_y + TILE_SIZE) then  -- top edge of player is above bottom edge of tile
              side_hit := '1'; 
            end if;

          elsif LEVEL_MAP(row * MAP_COLS + check_col) = TILE_SPIKE then

            if (px_i < tile_x + SPIKE_WIDTH and
                px_i + PLAYER_SIZE > tile_x and
                py_i + PLAYER_SIZE > tile_y + 8 and
                py_i < tile_y + SPIKE_HEIGHT) then
              spike_hit := '1';
            end if;

          end if;
        end if;
      end loop;
    end loop;

    side_collision  <= side_hit;
    spike_collision <= spike_hit;
  end process;

  -- Drive the physical interrupt output pin
  irq_vblank <= irq_vblank_i; -- Interrupt


  -- vblank is detected via pixel_clock and reliably transmitted to clk domain
  -- and a single-cycle game_tick is generated from its rising edge
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      vblank_meta <= '0';
      vblank_sync <= '0';
      vblank_last <= '0';
      game_tick   <= '0';

    elsif rising_edge(clk) then
      -- 2-FF Synchronization
      vblank_meta <= vblank_pix;
      vblank_sync <= vblank_meta;

      -- rising edge of vblank_sync?
      game_tick <= vblank_sync and not vblank_last;

      -- store old value
      vblank_last <= vblank_sync;
    end if;
  end process;

  -- camera
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      camera_x <= 0;
      level_finished_req <= '0';

    elsif rising_edge(clk) then
      level_finished_req <= '0';

      if game_reset_req = '1' then
        camera_x <= 0;

      elsif game_tick = '1' and game_state = RUNNING then
        if camera_x < LEVEL_END_X then
          camera_x <= camera_x + speed_reg;
        else
          level_finished_req <= '1';
        end if;
      end if;
    end if;
  end process;


  -- CPU MMIO Interface (Wishbone Protocol)
  -- depends on adress
  process (clk, system_reset) is
    variable y_next : integer;
    variable v_next : integer;
    variable px_i : integer;
    variable py_i : integer;
    variable tile_x : integer;
    variable tile_y : integer;
    variable landed_on_block : boolean;
    variable on_ground : boolean;
    variable on_block  : boolean;
    variable player_world_x : integer;
    variable base_col       : integer;
    variable check_col      : integer;

  begin
    if system_reset = '1' then
      player_x_reg <= to_unsigned(100, 32);
      player_y_reg <= to_unsigned(370, 32);
      bg_color_reg <= x"008";
      wb_ack_o     <= '0';
      velocity_y   <= 0;
      jump_request <= '0';
      score_reg         <= (others => '0');
      score_div_counter <= 0;
      game_state <= MENU;
      speed_reg  <= 3;
      game_over  <= '0';
      reset_delay_counter <= 0;

    elsif rising_edge(clk) then
      wb_ack_o <= '0';
      game_reset_req <= '0';

      if level_finished_req = '1' and game_state = RUNNING then
        -- game_over  <= '1';  
        game_state <= GAME_OVER_STATE;
      end if;

      -- btn_c mark as a jump only while running
      if game_state = RUNNING and btn_play = '1' then
        jump_request <= '1';
      end if;

      -- MENU
      -- btn_r = change speed and pause
      -- btn_c = start and jump
      if game_state = MENU then
        -- btn_r cycles speed: rollover
        if btn_menu = '1' then
          if speed_reg = 4 then
            speed_reg <= 3;
          else
            speed_reg <= 4;
          end if;
        end if;

        -- btn_c starts game
        if btn_play = '1' then
          game_state        <= RUNNING;
          game_over         <= '0';
          score_reg         <= (others => '0');
          score_div_counter <= 0;
          velocity_y        <= 0;
          jump_request      <= '0';
          game_reset_req    <= '1';
        end if;

      end if;

      -- RUNNING / PAUSED:
      -- btn_r = Pause / Resume
      if btn_menu = '1' then
        if game_state = RUNNING then
          game_state <= PAUSED;

        elsif game_state = PAUSED then
          game_state <= RUNNING;
        end if;
      end if;

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

          -- 0x1000_0010 CONTROL -  reset_game()
          when "0100" =>
            if wb_dat_i(0) = '1' then
              player_x_reg <= to_unsigned(100, 32);
              player_y_reg <= to_unsigned(370, 32);
              velocity_y   <= 0;
              game_reset_req <= '1';
              jump_request <= '0';
              score_reg         <= (others => '0');
              score_div_counter <= 0;
              game_state     <= MENU;
              game_over      <= '0';
              reset_delay_counter <= 0;
            end if;

          -- 0x1000_0018 SPEED
          when "0110" =>
            if to_integer(unsigned(wb_dat_i(3 downto 0))) < 3 then
              speed_reg <= 3;
            elsif to_integer(unsigned(wb_dat_i(3 downto 0))) > 4 then
              speed_reg <= 4;
            else
              speed_reg <= to_integer(unsigned(wb_dat_i(3 downto 0)));
            end if;

          when others =>
            null;

        end case;
      end if;
    end if;


    -- Hardware player physics
    if game_tick = '1' and game_state = RUNNING then
      y_next := to_integer(player_y_reg(9 downto 0));
      v_next := velocity_y; -- on ground

      px_i := to_integer(player_x_reg(9 downto 0));
      py_i := to_integer(player_y_reg(9 downto 0));

      -- is the player currently standing on the ground or on a real block?
      if py_i = PLAYER_GROUND_Y then
        on_ground := true;
      else
        on_ground := false;
      end if;
      on_block  := false;


      player_world_x := px_i + camera_x; 

      if player_world_x < MAP_START_X then
        base_col := -1;
      else
        base_col := (player_world_x - MAP_START_X) / TILE_STEP;
      end if;

      for row in 0 to MAP_ROWS - 1 loop
        tile_y := PLAYER_GROUND_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;    

        for col_offset in -1 to 1 loop
          check_col := base_col + col_offset;

          if check_col >= 0 and check_col < MAP_COLS then
            tile_x := MAP_START_X + check_col * TILE_STEP - camera_x;

            if LEVEL_MAP(row * MAP_COLS + check_col) = TILE_BLOCK then     
              if px_i < tile_x + TILE_STEP and
                px_i + PLAYER_SIZE > tile_x and
                py_i + PLAYER_SIZE = tile_y then
                on_block := true;
              end if;
            end if;

          end if;
        end loop;
      end loop;


      -- calculate jump/gravity 
      if (jump_request = '1' or jump_hold_i = '1') and
        (on_ground or on_block) then
        v_next := JUMP_STRENGTH;
      else
        v_next := velocity_y + GRAVITY; 
      end if;

      if v_next > 20 then
        v_next := 20;
      elsif v_next < -20 then
        v_next := -20;
      end if;

      y_next := y_next + v_next; -- up or down 

      -- does the player land on a block?
      landed_on_block := false;

      for row in 0 to MAP_ROWS - 1 loop
        tile_y := PLAYER_GROUND_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;    

        for col_offset in -1 to 1 loop
          check_col := base_col + col_offset;

          if check_col >= 0 and check_col < MAP_COLS then
            tile_x := MAP_START_X + check_col * TILE_STEP - camera_x;

            if LEVEL_MAP(row * MAP_COLS + check_col) = TILE_BLOCK then  
              if px_i < tile_x + TILE_STEP and 
                px_i + PLAYER_SIZE > tile_x and -- player is actually positioned horizontally on the block, so he will land
                v_next >= 0 and -- fällt
                py_i + PLAYER_SIZE <= tile_y and -- bottom edge of player above block
                y_next + PLAYER_SIZE >= tile_y then -- afterwards bottom edge at or below the block

                landed_on_block := true;
                y_next := tile_y - PLAYER_SIZE; -- position the player exactly on the top edge of the block
                v_next := 0; -- stop falling
              end if;
            end if;
          end if;
        end loop;
      end loop;

      -- otherwise land on ground
      if landed_on_block = false then
        if y_next > PLAYER_GROUND_Y then
          y_next := PLAYER_GROUND_Y;
          v_next := 0;
        end if;
      end if;

      -- not neseccary actually 
      if y_next < 0 then
        y_next := 0;
        v_next := 0;
      end if;
      -- store
      player_y_reg <= to_unsigned(y_next, 32);  
      velocity_y   <= v_next;
      jump_request <= '0';
    end if;


   -- score increases after 60 game ticks, i.e. every second
      if game_tick = '1' and  game_state = RUNNING then
        if score_div_counter = 59 then
          score_div_counter <= 0;
          score_reg <= score_reg + 1;
        else
          score_div_counter <= score_div_counter + 1;
        end if;

        if side_collision = '1' or spike_collision = '1' then
          game_over <= '1';
          game_state <= GAME_OVER_STATE;
        end if;
      end if;

      -- after Game Over / Level-end back to menu
      if game_tick = '1' then
        if game_state = GAME_OVER_STATE then
          if reset_delay_counter = 90 then -- returns to the menu 1.5 seconds after game over
            player_x_reg <= to_unsigned(100, 32);
            player_y_reg <= to_unsigned(370, 32);
            velocity_y   <= 0;
            jump_request <= '0';
            score_reg         <= (others => '0');
            score_div_counter <= 0;
            game_over      <= '0';
            game_state     <= MENU;
            game_reset_req <= '1';
            reset_delay_counter <= 0;
          else
            reset_delay_counter <= reset_delay_counter + 1;
          end if;

      else
        reset_delay_counter <= 0;
      end if;
    end if;

    end if;
  end process;


    -- read operation; the CPU receives the appropriate value based on the address
    process (all) is
    begin
      case wb_adr_i(5 downto 2) is

        when "0000" =>
          wb_dat_o <= std_logic_vector(player_x_reg);

        when "0001" =>
          wb_dat_o <= std_logic_vector(player_y_reg);

        when "0010" =>
          wb_dat_o <= x"00000" & bg_color_reg;

        when "0100" =>
          wb_dat_o <= (31 downto 1 => '0') & game_over;

        when "0101" =>
          wb_dat_o <= std_logic_vector(score_reg);
        
        when "0110" =>
          wb_dat_o <= std_logic_vector(to_unsigned(speed_reg, 32));

        when others =>
          wb_dat_o <= (others => '0');

      end case;
    end process;


  -- direct mathematical rendering 
  process (all) is
    variable sx         : integer;
    variable sy         : integer;
    variable px_i         : integer;
    variable py_i         : integer;
    variable progress_w : integer;
    
    variable world_x    : integer;
    variable tile_col   : integer;
    variable tile_row   : integer;
    variable tile_index : integer;
    variable tile_val   : integer;
    variable local_x    : integer;
    variable local_y    : integer;
  begin

    px_i := to_integer(player_x_reg(9 downto 0)); 
    py_i := to_integer(player_y_reg(9 downto 0));

    -- activ VGA area
    if (h_cnt >= 144 and h_cnt < 784 and v_cnt >= 35 and v_cnt < 515) then -- 640 x 480

      sx := h_cnt - 144;
      sy := v_cnt - 35;

      -- load background color
      color <= bg_color_reg;

      -- bottom
      if sy >= GROUND_Y then
        color <= x"014"; -- dark green
      end if;

    -- direct mapping
    world_x := sx + camera_x;

    if world_x >= MAP_START_X and world_x < LEVEL_END_X then

      if sy >= 310 and sy < 400 then

        tile_col := (world_x - MAP_START_X) / TILE_STEP;
        tile_row := (sy - 310) / TILE_SIZE;

        -- determine the position within the tile from 0 to 31 or 0 to 30
        local_x  := (world_x - MAP_START_X) mod TILE_STEP; -- distance from the left
        local_y  := (sy - 310) mod TILE_SIZE; -- distance from the top

        tile_index := tile_row * MAP_COLS + tile_col;
        tile_val   := LEVEL_MAP(tile_index);

        if tile_val = TILE_BLOCK then
          color <= x"FF0"; -- yellow

        elsif tile_val = TILE_SPIKE then
          if local_x < SPIKE_WIDTH and local_y < SPIKE_HEIGHT then

            -- draw triangle 
            if local_y >= SPIKE_HEIGHT - local_x and
              local_x < SPIKE_WIDTH / 2 then --
              color <= x"F00"; -- red

            elsif local_y >= SPIKE_HEIGHT - ((SPIKE_WIDTH - 1) - local_x) and
                  local_x >= SPIKE_WIDTH / 2 then
              color <= x"F00"; -- red
            end if;

          end if;
        end if;

      end if;
    end if;    

      -- progress bar at the top of the screen
      progress_w := (camera_x * 600) / LEVEL_END_X;
      if progress_w > 600 then
        progress_w := 600;
      end if;

      if (sy >= 10 and sy < 18 and sx >= 20 and sx < 620) then
        color <= x"333"; -- background grey
      end if;

      if (sy >= 10 and sy < 18 and sx >= 20 and sx < 20 + progress_w) then
        color <= x"0F0"; -- progess green
      end if;


      -- draw player-cube 
      if (sx >= px_i and sx < px_i + PLAYER_SIZE and
          sy >= py_i and sy < py_i + PLAYER_SIZE) then
        if game_over = '1' then
          color <= x"F00"; -- red on collision
        else
          color <= x"0F4"; -- green during gameplay
        end if;
      end if;
    
      -- menu
      if game_state = MENU then
        color <= x"111"; -- black

        -- speed bar in menu
        if sy >= 210 and sy < 230 and sx >= 220 and sx < 300 then
          color <= x"333"; -- dark grey
        end if;

        if sy >= 210 and sy < 230 and sx >= 220 and sx < 220 + (speed_reg - 2) * 40 then
          color <= x"0F0"; --  bright green 
        end if;

        -- player in menu
        if sx >= 100 and sx < 130 and sy >= 370 and sy < 400 then
          color <= x"0F4"; -- green
        end if;
      end if;

      -- pause
      if game_state = PAUSED then
        if (sy >= 20 and sy < 60 and sx >= 560 and sx < 570) or
           (sy >= 20 and sy < 60 and sx >= 585 and sx < 595) then
          color <= x"F6C"; -- pink
        end if;
      end if;
            
    else
      color <= x"000"; -- black outside the active area
    end if;
  end process;       

  -- Generate structural timing Sync Assertions, activ 0
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

  -- VBlank-level in pixel_clock
  -- -- 1, as soon as the visible area is complete
  process (pixel_clock, system_reset) is
  begin
    if system_reset = '1' then
      vblank_pix <= '0';

    elsif rising_edge(pixel_clock) then
      if v_cnt >= 515 then
        vblank_pix <= '1';
      else
        vblank_pix <= '0';
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

  -- 
  process (pixel_clock) is
  begin
    if rising_edge(pixel_clock) then
      color_pipe(0) <= color;
      color_pipe(1) <= color_pipe(0);
      color_pipe(2) <= color_pipe(1);
      color_pipe(3) <= color_pipe(2);
    end if;
  end process;

  color_delayed <= color_pipe(3);

  -- Display Blanking Multi-plexer
  -- 3. Final Output MUST be clocked to eliminate combinatorial glitches:
  process (pixel_clock) is
  begin
    if rising_edge(pixel_clock) then
      if (blank_reg(3) = '1') then
        vga_red   <= (others => '0');
        vga_green <= (others => '0');
        vga_blue  <= (others => '0');
      else
        -- Make sure 'color' here matches the 4-cycle delay pipeline
        vga_red   <= color_delayed(11 downto 8);
        vga_green <= color_delayed(7 downto 4);
        vga_blue  <= color_delayed(3 downto 0);
      end if;
      h_sync <= hsync_reg(3);
      v_sync <= vsync_reg(3);
    end if;
  end process;


end architecture behavioral;
