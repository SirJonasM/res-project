library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.game_pkg.all;

entity game_physics_engine is
  port (
    clk                 : in    std_logic;
    system_reset        : in    std_logic;
    vblank_pix          : in    std_logic;
    
    -- Inputs from buttons
    btn_menu            : in    std_logic;
    jump_hold_i         : in    std_logic;
    btn_play            : in    std_logic;
    
    -- Inputs from MMIO Write Requests
    wb_reset_req        : in    std_logic;
    wb_speed_write      : in    std_logic;
    wb_speed_val        : in    integer range 3 to 4;

    -- Dynamic outputs back to MMIO and Painter Pipeline
    player_x            : out   unsigned(31 downto 0);
    player_y            : out   unsigned(31 downto 0);
    score               : out   unsigned(31 downto 0);
    speed_reg_out       : out   integer range 3 to 4;
    game_state_one_hot  : out   std_logic_vector(3 downto 0);
    game_state_out      : out   std_logic_vector(1 downto 0);
    camera_x_out        : out   integer range 0 to 16000;
    camera_progress     : out   integer;
    game_over_out       : out   std_logic;
    irq_vblank          : out   std_logic
  );
end entity game_physics_engine;

architecture behavioral of game_physics_engine is
  -- Internal States
  signal player_x_reg : unsigned(31 downto 0) := to_unsigned(100, 32);
  -- Match PLAYER_GROUND_Y (384) instead of 370 to prevent initial glitching
  signal player_y_reg : unsigned(31 downto 0) := to_unsigned(384, 32); 
  signal score_reg    : unsigned(31 downto 0) := (others => '0');
  signal speed_reg    : integer range 3 to 4  := 3;
  
  type game_state_t is (MENU, RUNNING, PAUSED, GAME_OVER_STATE);
  signal game_state   : game_state_t := MENU;

  signal camera_x          : integer range 0 to 16000 := 0;
  signal camera_progress_w : integer := 0;
  signal game_over          : std_logic := '0';
  signal irq_vblank_i       : std_logic := '0';

  -- Physics Constants (All optimized to powers/multiples of 2)
  constant PLAYER_SIZE     : integer := 32;   -- 2^5
  constant JUMP_STRENGTH   : integer := -12; 
  constant GRAVITY         : integer := 1;    
  constant PLAYER_GROUND_Y : integer := 384;  -- Multiple of 32
  constant TILE_SIZE       : integer := 32;   -- 2^5
  constant TILE_STEP       : integer := 32;   -- 2^5
  constant MAP_START_X     : integer := 512;  -- 2^9
  constant LEVEL_END_X     : integer := MAP_START_X + MAP_COLS * TILE_STEP; 

  -- FIXED-POINT RECIPROCAL MATH FOR REPLACING THE DIVIDER:
  -- We compute: (600 * 65536) / LEVEL_END_X dynamically as a constant value at compile time.
  -- This allows us to multiply by this constant and shift right by 16 bits later.
  constant CAM_SCALE_FACTOR : unsigned(31 downto 0) := to_unsigned((600 * 65536) / LEVEL_END_X, 32);

  constant SPIKE_WIDTH     : integer := 16;   -- 2^4
  constant SPIKE_HEIGHT    : integer := 32;   -- 2^5

  -- Clock Domain Synchronization
  signal vblank_meta, vblank_sync, vblank_last, game_tick : std_logic := '0';

  -- Physics Control Triggers
  signal velocity_y          : integer range -20 to 20 := 0;
  signal jump_request         : std_logic := '0';
  signal side_collision       : std_logic := '0';
  signal spike_collision      : std_logic := '0';
  signal game_reset_req       : std_logic := '0';
  signal level_finished_req : std_logic := '0';
  signal reset_delay_counter: integer range 0 to 90 := 0;
  signal score_div_counter  : integer range 0 to 59 := 0;

  -- Pipeline Registers for Collision Paths
  signal p1_px, p1_py, p1_world_x, p1_base_col : integer := 0;
  type col_array_t is array (0 to 2) of integer;
  signal p2_check_cols : col_array_t := (others => 0);
  type tile_val_array_t is array (0 to 2, 0 to 2) of integer;
  signal p3_tile_vals  : tile_val_array_t := (others => (others => 0));
  signal p3_tile_x     : col_array_t := (others => 0);
  signal p4_side_hit, p4_spike_hit : std_logic := '0';

  -- Camera Math Pipeline Registers (Widened to hold scale factor products safely)
  signal cam_mult_reg : unsigned(63 downto 0) := (others => '0');

begin
  -- Output Assignments
  player_x        <= player_x_reg;
  player_y        <= player_y_reg;
  score           <= score_reg;
  speed_reg_out   <= speed_reg;
  camera_x_out    <= camera_x;
  camera_progress <= camera_progress_w;
  game_over_out   <= game_over;
  irq_vblank      <= irq_vblank_i;

  with game_state select game_state_one_hot <=
    "0001" when MENU,
    "0010" when RUNNING,
    "0100" when PAUSED,
    "1000" when GAME_OVER_STATE,
    "0000" when others;

  with game_state select game_state_out <=
    "00" when MENU,
    "01" when RUNNING,
    "10" when PAUSED,
    "11" when GAME_OVER_STATE;

  -- Synchronization Pulse Process
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      vblank_meta <= '0'; vblank_sync <= '0'; vblank_last <= '0'; game_tick <= '0';
    elsif rising_edge(clk) then
      vblank_meta <= vblank_pix;
      vblank_sync <= vblank_meta;
      game_tick   <= vblank_sync and not vblank_last;
      vblank_last <= vblank_sync;
    end if;
  end process;

  -- Pipelined Collision Matrix Engine
  pipelined_collision_proc : process(clk, system_reset)
    variable shifted_val : unsigned(31 downto 0);
    variable tile_y      : integer;
  begin
    if system_reset = '1' then
      p1_px <= 0; p1_py <= 0; p1_base_col <= 0; p1_world_x <= 0;
      p2_check_cols <= (others => 0); p3_tile_x <= (others => 0);
      p3_tile_vals <= (others => (others => 0));
      p4_side_hit <= '0'; p4_spike_hit <= '0';
      side_collision <= '0'; spike_collision <= '0';
    elsif rising_edge(clk) then
      -- STAGE 1: Latch coordinates
      p1_px <= to_integer(player_x_reg(9 downto 0));
      p1_py <= to_integer(player_y_reg(9 downto 0));
      p1_world_x <= to_integer(player_x_reg(9 downto 0)) + camera_x;
      
      if (p1_world_x < MAP_START_X) then
        p1_base_col <= -1;
      else
        shifted_val := to_unsigned(p1_world_x - MAP_START_X, 32);
        -- Optimized: Clean right shift by 5 bits instead of a division by 32
        p1_base_col <= to_integer(shift_right(shifted_val, 5));
      end if;

      -- STAGE 2: Calculate columns
      p2_check_cols(0) <= p1_base_col - 1;
      p2_check_cols(1) <= p1_base_col;
      p2_check_cols(2) <= p1_base_col + 1;
      
      -- STAGE 3: Fetch Tile Values and Coordinates
      for r in 0 to MAP_ROWS - 1 loop
        for c in 0 to 2 loop
          if p2_check_cols(c) >= 0 and p2_check_cols(c) < MAP_COLS then
            p3_tile_vals(r, c) <= LEVEL_MAP(r * MAP_COLS + p2_check_cols(c));
          else
            p3_tile_vals(r, c) <= 0;
          end if;
        end loop;
      end loop;
      
      for c in 0 to 2 loop
        -- Optimized: Shift left by 5 bits instead of multiplying by 32
        p3_tile_x(c) <= MAP_START_X + to_integer(shift_left(to_unsigned(p2_check_cols(c), 16), 5)) - camera_x;
      end loop;

      -- STAGE 4: Combinatorial Boundary Bounding Box Evaluation
      p4_side_hit  <= '0';
      p4_spike_hit <= '0';
      for r in 0 to MAP_ROWS - 1 loop
        -- Optimized: (MAP_ROWS - 1 - r) * 32 becomes a clean 5-bit shift left
        tile_y := PLAYER_GROUND_Y - to_integer(shift_left(to_unsigned(MAP_ROWS - 1 - r, 16), 5));
        for c in 0 to 2 loop
          if p3_tile_vals(r, c) = TILE_BLOCK then
            if (p1_px < p3_tile_x(c) + TILE_STEP and 
                p1_px + PLAYER_SIZE > p3_tile_x(c) and 
                p1_py + PLAYER_SIZE > tile_y + 12 and 
                p1_py < tile_y + TILE_SIZE) then
              p4_side_hit <= '1';
            end if;
          elsif p3_tile_vals(r, c) = TILE_SPIKE then
            if (p1_px < p3_tile_x(c) + SPIKE_WIDTH and 
                p1_px + PLAYER_SIZE > p3_tile_x(c) and 
                p1_py + PLAYER_SIZE > tile_y + 8 and 
                p1_py < tile_y + SPIKE_HEIGHT) then
              p4_spike_hit <= '1';
            end if;
          end if;
        end loop;
      end loop;

      -- STAGE 5: Final registered hit output
      side_collision  <= p4_side_hit;
      spike_collision <= p4_spike_hit;
    end if;
  end process;

  -- Pipelined Camera Progress and Advancement Logic (Zero Dividers!)
  process (clk, system_reset) is
    variable final_progress : unsigned(31 downto 0);
  begin
    if system_reset = '1' then
      camera_x          <= 0;
      level_finished_req <= '0';
      cam_mult_reg      <= (others => '0');
      camera_progress_w <= 0;
    elsif rising_edge(clk) then
      level_finished_req <= '0';
      
      if game_reset_req = '1' then
        camera_x          <= 0;
        cam_mult_reg      <= (others => '0');
        camera_progress_w <= 0;
      elsif game_tick = '1' and game_state = RUNNING then
        if camera_x < LEVEL_END_X then
          camera_x <= camera_x + speed_reg;
          
          -- Pipeline Stage 1: Multiply by our pre-scaled fraction factor constant.
          -- This maps efficiently to hardware DSP blocks.
          cam_mult_reg <= to_unsigned(camera_x + speed_reg, 32) * CAM_SCALE_FACTOR;
          
          -- Pipeline Stage 2: Instead of dividing, we right-shift by 16 bits to 
          -- clear out our fractional scale factor space. Costs 0 logic elements.
          final_progress := unsigned(shift_right(cam_mult_reg, 16)(31 downto 0));
          camera_progress_w <= to_integer(final_progress);
        else
          level_finished_req <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Physics Core Execution Loop Process
  process (clk, system_reset) is
    variable y_next, v_next, px_i, py_i : integer;
    variable on_ground, on_block        : boolean;
  begin
    if system_reset = '1' then
      player_x_reg        <= to_unsigned(100, 32); 
      player_y_reg        <= to_unsigned(384, 32);
      velocity_y          <= 0; 
      jump_request         <= '0'; 
      score_reg           <= (others => '0');
      score_div_counter   <= 0; 
      game_state          <= MENU; 
      speed_reg           <= 3;
      game_over           <= '0'; 
      reset_delay_counter <= 0; 
      irq_vblank_i        <= '0'; 
      game_reset_req      <= '0';
    elsif rising_edge(clk) then
      game_reset_req <= '0';
      irq_vblank_i   <= '0';

      -- Check CPU MMIO System Write Forces
      if wb_reset_req = '1' then
        player_x_reg        <= to_unsigned(100, 32); 
        player_y_reg        <= to_unsigned(384, 32);
        velocity_y          <= 0; 
        jump_request         <= '0'; 
        score_reg           <= (others => '0');
        score_div_counter   <= 0; 
        game_state          <= MENU; 
        irq_vblank_i        <= '1';
        game_over           <= '0'; 
        reset_delay_counter <= 0; 
        game_reset_req      <= '1';
      end if;

      if wb_speed_write = '1' then
        speed_reg <= wb_speed_val;
      end if;

      -- State Machine and Interface Engine
      if level_finished_req = '1' and game_state = RUNNING then
        game_state <= GAME_OVER_STATE; irq_vblank_i <= '1';
      end if;

      if game_state = RUNNING and btn_play = '1' then
        jump_request <= '1';
      end if;

      if game_state = MENU then
        if btn_menu = '1' then
          speed_reg <= 4 when speed_reg = 3 else 3;
        end if;
        if btn_play = '1' then
          game_state          <= RUNNING; 
          irq_vblank_i        <= '1'; 
          game_over           <= '0';
          score_reg           <= (others => '0'); 
          score_div_counter   <= 0;
          velocity_y          <= 0; 
          jump_request         <= '0'; 
          game_reset_req      <= '1';
        end if;
      end if;

      if btn_menu = '1' then
        if game_state = RUNNING then
          irq_vblank_i <= '1'; game_state <= PAUSED;
        elsif game_state = PAUSED then
          irq_vblank_i <= '1'; game_state <= RUNNING;
        end if;
      end if;

      -- Hardware Kinematics Pipeline Execution
      if game_tick = '1' and game_state = RUNNING then
        y_next := to_integer(player_y_reg(9 downto 0));
        v_next := velocity_y;
        px_i   := to_integer(player_x_reg(9 downto 0));
        py_i   := to_integer(player_y_reg(9 downto 0));
        
        on_ground := (py_i = PLAYER_GROUND_Y);
        on_block := (p4_side_hit = '1'); 

        if (jump_request = '1' or jump_hold_i = '1') and (on_ground or on_block) then
          v_next := JUMP_STRENGTH;
        else
          v_next := velocity_y + GRAVITY;
        end if;

        if v_next > 20 then 
          v_next := 20; 
        elsif v_next < -20 then 
          v_next := -20; 
        end if;
        
        y_next := y_next + v_next;

        -- Check floor constraints
        if (p4_side_hit = '1') and v_next >= 0 then
           v_next := 0;
        end if;

        if y_next > PLAYER_GROUND_Y then
          y_next := PLAYER_GROUND_Y; 
          v_next := 0;
        end if;
        
        if y_next < 0 then 
          y_next := 0; 
          v_next := 0; 
        end if;

        player_y_reg <= to_unsigned(y_next, 32);
        velocity_y   <= v_next;
        jump_request <= '0';
      end if;

      -- Scoring Management (Counter based instead of Modulo arithmetic)
      if game_tick = '1' and game_state = RUNNING then
        if score_div_counter = 59 then
          score_div_counter <= 0; 
          score_reg         <= score_reg + 1;
        else
          score_div_counter <= score_div_counter + 1;
        end if;

        if side_collision = '1' or spike_collision = '1' then
          game_over <= '1'; irq_vblank_i <= '1'; game_state <= GAME_OVER_STATE;
        end if;
      end if;

      -- Reset Auto-Delay Handshaking
      if game_tick = '1' then
        if game_state = GAME_OVER_STATE then
          if reset_delay_counter = 90 then
            player_x_reg        <= to_unsigned(100, 32); 
            player_y_reg        <= to_unsigned(384, 32);
            velocity_y          <= 0; 
            jump_request         <= '0'; 
            score_reg           <= (others => '0');
            score_div_counter   <= 0; 
            game_over           <= '0'; 
            game_state          <= MENU;
            irq_vblank_i        <= '1'; 
            game_reset_req      <= '1'; 
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
end architecture behavioral;
