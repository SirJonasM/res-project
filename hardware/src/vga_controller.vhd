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
    jump_i       : in    std_logic;
    jump_hold_i : in std_logic;
    start_i      : in    std_logic
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
  signal bg_color_reg : std_logic_vector(11 downto 0) := (others => '0');

  -- Neue Register hinzufügen für Position
  signal player_x_reg : unsigned(31 downto 0) := to_unsigned(100, 32);
  signal player_y_reg : unsigned(31 downto 0) := to_unsigned(370, 32);

  constant PLAYER_SIZE : integer := 30;
  constant GROUND_Y    : integer := 400;

  -- RGB, HSync und VSync sauber mit pixel_clock registriert werden
  type color_pipe_t is array (0 to 3) of std_logic_vector(11 downto 0);
  signal color_pipe    : color_pipe_t := (others => (others => '0'));
  signal color_delayed : std_logic_vector(11 downto 0);

  -- game tick
  signal game_tick    : std_logic := '0';
  signal tick_counter : integer range 0 to 1666665 := 0;

  -- moving obstacle
  constant OBSTACLE_WIDTH  : integer := 30;
  constant OBSTACLE_HEIGHT : integer := 30;
  constant OBSTACLE_Y      : integer := 370;
  --constant OBSTACLE_SPEED  : integer := 2;
  signal obstacle_x : integer range -50 to 700 := 640;

  -- jumping cube
  signal velocity_y   : integer range -20 to 20 := 0;
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
  constant SPIKE_Y      : integer := 370;
  --constant SPIKE_SPEED  : integer := 3;

  signal spike_x : integer range -50 to 700 := 640;
  signal spike_collision : std_logic := '0';

  -- score
  signal score_reg : unsigned(31 downto 0) := (others => '0');
  signal score_div_counter : integer range 0 to 59 := 0;

  -- speed
  signal speed_reg : integer range 3 to 5 := 3;

  type game_state_t is (MENU, RUNNING, PAUSED, GAME_OVER_STATE);
  signal game_state : game_state_t := MENU;

  --tilemap
  constant TILE_EMPTY : integer := 0;
  constant TILE_BLOCK : integer := 1;
  constant TILE_SPIKE : integer := 2;

  constant TILE_SIZE  : integer := 30;
  constant MAP_START_X : integer := 640;

  constant MAP_ROWS : integer := 3;
  constant MAP_COLS : integer := 36;

  type tile_row_t is array (0 to MAP_COLS - 1) of integer range 0 to 2;
  type tile_map_t is array (0 to MAP_ROWS - 1) of tile_row_t;


  constant LEVEL_MAP : tile_map_t := (
    -- row 2 (oberste Reihe)
    (
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY
    ),

    -- row 1 (mittlere Reihe)
    (
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY
    ),

    -- row 0 (unterste Reihe)
    (
      TILE_EMPTY, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY,
      TILE_EMPTY, TILE_SPIKE, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_SPIKE, TILE_EMPTY,
      TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
      TILE_SPIKE, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY, TILE_EMPTY,
      TILE_SPIKE, TILE_EMPTY, TILE_BLOCK, TILE_BLOCK, TILE_BLOCK, TILE_EMPTY
    )
  );

  constant LEVEL_END_X : integer := MAP_START_X + MAP_COLS * TILE_SIZE;
  signal camera_x : integer range 0 to 4095 := 0;

begin

  -- collision
    collision_proc : process (all) is
      variable px_i      : integer;
      variable py_i      : integer;
      variable tile_x    : integer;
      variable tile_y    : integer;
      variable side_hit  : std_logic;
      variable spike_hit : std_logic;
    begin
      px_i := to_integer(player_x_reg(9 downto 0));
      py_i := to_integer(player_y_reg(9 downto 0));

      side_hit  := '0';
      spike_hit := '0';

      for row in 0 to MAP_ROWS - 1 loop
        tile_y := OBSTACLE_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;

        for col in 0 to MAP_COLS - 1 loop
          tile_x := MAP_START_X + col * TILE_SIZE - camera_x;

          if LEVEL_MAP(row)(col) = TILE_BLOCK then

            if (px_i < tile_x + TILE_SIZE and
                px_i + PLAYER_SIZE > tile_x and
                py_i + PLAYER_SIZE > tile_y + 12 and
                py_i < tile_y + TILE_SIZE) then
              side_hit := '1';
            end if;

          elsif LEVEL_MAP(row)(col) = TILE_SPIKE then

            if (px_i < tile_x + SPIKE_WIDTH and
                px_i + PLAYER_SIZE > tile_x and
                py_i < tile_y + SPIKE_HEIGHT and
                py_i + PLAYER_SIZE > tile_y + 8) then
              spike_hit := '1';
            end if;

          end if;
        end loop;
      end loop;

      side_collision  <= side_hit;
      spike_collision <= spike_hit;
    end process;

  -- Drive the physical interrupt output pin
  irq_vblank <= irq_vblank_i;


  -- game tick
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      tick_counter <= 0;
      game_tick    <= '0';

    elsif rising_edge(clk) then
      if tick_counter = 1666665 then
        tick_counter <= 0;
        game_tick    <= '1';
      else
        tick_counter <= tick_counter + 1;
        game_tick    <= '0';
      end if;
    end if;
  end process;

  -- camera
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      camera_x <= 0;

    elsif rising_edge(clk) then
      if game_reset_req = '1' then
        camera_x <= 0;

      elsif game_tick = '1' and game_state = RUNNING then
        if camera_x < LEVEL_END_X then
          camera_x <= camera_x + speed_reg;
        else
          camera_x <= 0;
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- CPU MMIO Interface (Wishbone Protocol)
  -- anhängig von der Adresse 
  -- =========================================================================
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
  begin
    if system_reset = '1' then
      player_x_reg <= to_unsigned(100, 32);
      player_y_reg <= to_unsigned(370, 32);
      bg_color_reg <= x"BCF";
      wb_ack_o     <= '0';
      velocity_y   <= 0;
      jump_request <= '0';
      score_reg         <= (others => '0');
      score_div_counter <= 0;
      game_state <= MENU;
      speed_reg  <= 3;
      game_over  <= '0';

    elsif rising_edge(clk) then
      wb_ack_o <= '0';
      game_reset_req <= '0';

      -- btnC nur während RUNNING als Sprung merken
      if game_state = RUNNING and jump_i = '1' then
        jump_request <= '1';
      end if;

      -- MENU:
      -- btnR = Speed ändern
      -- btnC = Start / bestätigen
      if game_state = MENU then

        -- btnR cycles speed: 3 -> 4 -> 5 -> 3
        if start_i = '1' then
          if speed_reg = 5 then
            speed_reg <= 3;
          else
            speed_reg <= speed_reg + 1;
          end if;
        end if;

        -- btnC confirms and starts game
        if jump_i = '1' then
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
      -- btnR = Pause / Resume
      if start_i = '1' then

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

          -- 0x1000_0010 CONTROL - zurücksetzen reset_game()
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
            end if;

          -- 0x1000_0018 SPEED
          when "0110" =>
            if to_integer(unsigned(wb_dat_i(3 downto 0))) < 3 then
              speed_reg <= 3;
            elsif to_integer(unsigned(wb_dat_i(3 downto 0))) > 5 then
              speed_reg <= 5;
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
      v_next := velocity_y;

      px_i := to_integer(player_x_reg(9 downto 0));
      py_i := to_integer(player_y_reg(9 downto 0));

      -- 1) Erst prüfen: steht der Player gerade auf Boden oder echtem Block?
      on_ground := (py_i = PLAYER_GROUND_Y);
      on_block  := false;

      for row in 0 to MAP_ROWS - 1 loop
        tile_y := OBSTACLE_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;

        for col in 0 to MAP_COLS - 1 loop
          tile_x := MAP_START_X + col * TILE_SIZE - camera_x;

          if LEVEL_MAP(row)(col) = TILE_BLOCK then
            if px_i < tile_x + TILE_SIZE and
              px_i + PLAYER_SIZE > tile_x and
              py_i + PLAYER_SIZE = tile_y then
              on_block := true;
            end if;
          end if;
        end loop;
      end loop;

      -- 2) Jetzt erst springen/Gravity berechnen
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

      y_next := y_next + v_next;

      -- 3) Nach Bewegung prüfen: landet der Player auf einem Block?
      landed_on_block := false;

      for row in 0 to MAP_ROWS - 1 loop
        tile_y := OBSTACLE_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;

        for col in 0 to MAP_COLS - 1 loop
          tile_x := MAP_START_X + col * TILE_SIZE - camera_x;

          if LEVEL_MAP(row)(col) = TILE_BLOCK then
            if px_i < tile_x + TILE_SIZE and
              px_i + PLAYER_SIZE > tile_x and
              v_next >= 0 and
              py_i + PLAYER_SIZE <= tile_y and
              y_next + PLAYER_SIZE >= tile_y then

              landed_on_block := true;
              y_next := tile_y - PLAYER_SIZE;
              v_next := 0;
            end if;
          end if;
        end loop;
      end loop;

      -- 4) Sonst auf Boden landen
      if landed_on_block = false then
        if y_next > PLAYER_GROUND_Y then
          y_next := PLAYER_GROUND_Y;
          v_next := 0;
        end if;
      end if;

      -- 5) Obere Bildschirmgrenze
      if y_next < 0 then
        y_next := 0;
        v_next := 0;
      end if;

      player_y_reg <= to_unsigned(y_next, 32);
      velocity_y   <= v_next;
      jump_request <= '0';
    end if;

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

  -- =========================================================================
  -- Video Timing and Rendering Engine (Pixel Clock Domain)
  -- =========================================================================
  -- Drive color from the MMIO register
    process (all) is
    variable sx : integer;
    variable sy : integer;
    variable px : integer;
    variable py : integer;
    variable tile_x  : integer;
    variable tile_y : integer;
    variable local_x : integer;
    variable local_y : integer;
  begin

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
        color <= x"014";
      end if;

      -- draw tilemap
      for row in 0 to MAP_ROWS - 1 loop
        tile_y := OBSTACLE_Y - (MAP_ROWS - 1 - row) * TILE_SIZE;

        for col in 0 to MAP_COLS - 1 loop
          tile_x := MAP_START_X + col * TILE_SIZE - camera_x;

          if LEVEL_MAP(row)(col) = TILE_BLOCK then

            if (sx >= tile_x and sx < tile_x + TILE_SIZE and
                sy >= tile_y and sy < tile_y + TILE_SIZE) then
              color <= x"FF0"; -- gelb
            end if;

          elsif LEVEL_MAP(row)(col) = TILE_SPIKE then

            if (sx >= tile_x and sx < tile_x + SPIKE_WIDTH and
                sy >= tile_y and sy < tile_y + SPIKE_HEIGHT) then

              local_x := sx - tile_x;
              local_y := sy - tile_y;

              if local_y >= SPIKE_HEIGHT - local_x and
                local_x < SPIKE_WIDTH / 2 then
                color <= x"F00"; -- rot

              elsif local_y >= SPIKE_HEIGHT - ((SPIKE_WIDTH - 1) - local_x) and
                    local_x >= SPIKE_WIDTH / 2 then
                color <= x"F00"; -- rot
              end if;

            end if;

          end if;
        end loop;
      end loop;

      -- progress bar background
      if (sy >= 10 and sy < 18 and sx >= 20 and sx < 620) then
        color <= x"333";
      end if;

      -- progress bar fill
      if (sy >= 10 and sy < 18 and sx >= 20 and sx < 20 + to_integer(score_reg(15 downto 0)) and
          to_integer(score_reg(15 downto 0)) < 600) then
        color <= x"0F0";
      end if;

      -- player cube
      if (sx >= px and sx < px + PLAYER_SIZE and
          sy >= py and sy < py + PLAYER_SIZE) then

        if game_over = '1' then
          color <= x"F00"; -- rot 
        else
          color <= x"0F4"; -- grün
        end if;

      end if;
    
      if game_state = MENU then
        color <= x"111";

        -- Speed bar background
        if sy >= 210 and sy < 230 and sx >= 220 and sx < 340 then
          color <= x"333";
        end if;

        -- Speed bar fill: Speed 3 = 1 Balken, Speed 4 = 2, Speed 5 = 3
        if sy >= 210 and sy < 230 and
          sx >= 220 and sx < 220 + (speed_reg - 2) * 40 then
          color <= x"0F0";
        end if;

        -- player preview
        if sx >= 100 and sx < 130 and sy >= 370 and sy < 400 then
          color <= x"0F4";
        end if;
      end if;

      if game_state = PAUSED then
        -- kleines Pause-Symbol oben rechts
        if sy >= 20 and sy < 60 and sx >= 560 and sx < 570 then
          color <= x"F6C";
        end if;

        if sy >= 20 and sy < 60 and sx >= 585 and sx < 595 then
          color <= x"F6C";
        end if;
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
