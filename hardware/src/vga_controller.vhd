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
  constant OBSTACLE_SPEED  : integer := 2;
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
  constant SPIKE_SPEED  : integer := 3;

  signal spike_x : integer range -50 to 700 := 600;
  signal spike_collision : std_logic := '0';

  -- score
  signal score_reg : unsigned(31 downto 0) := (others => '0');
  signal score_div_counter : integer range 0 to 59 := 0;

  -- speed
  signal speed_reg : integer range 1 to 5 := 3;

  type game_state_t is (MENU, RUNNING, GAME_OVER_STATE);
  signal game_state : game_state_t := MENU;


begin

  -- collision
  side_collision <= '1' when
    (
      -- X overlap
      to_integer(player_x_reg(9 downto 0)) < obstacle_x + OBSTACLE_WIDTH and
      to_integer(player_x_reg(9 downto 0)) + PLAYER_SIZE > obstacle_x and

      -- Y overlap, aber nur wenn Player deutlich in die Seite reinragt
      to_integer(player_y_reg(9 downto 0)) + PLAYER_SIZE > OBSTACLE_Y + 4 and
      to_integer(player_y_reg(9 downto 0)) < OBSTACLE_Y + OBSTACLE_HEIGHT
    )
  else '0';

  spike_collision <= '1' when
    (
      to_integer(player_x_reg(9 downto 0)) < spike_x + SPIKE_WIDTH and
      to_integer(player_x_reg(9 downto 0)) + PLAYER_SIZE > spike_x and
      to_integer(player_y_reg(9 downto 0)) < SPIKE_Y + SPIKE_HEIGHT and
      to_integer(player_y_reg(9 downto 0)) + PLAYER_SIZE > SPIKE_Y + 8
    )
  else '0';

  -- Drive the physical interrupt output pin
  irq_vblank <= irq_vblank_i;

  -- spike 
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      spike_x <= 600;

    elsif rising_edge(clk) then

      if game_reset_req = '1' then
        spike_x <= 600;

      elsif game_tick = '1' and game_state = RUNNING then
        if spike_x > -SPIKE_WIDTH then
          spike_x <= spike_x - speed_reg;
        else
          spike_x <= 600;
        end if;
      end if;

    end if;
  end process;

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

  -- obstacle
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      obstacle_x <= 640;

    elsif rising_edge(clk) then

      if game_reset_req = '1' then
        obstacle_x <= 640;

      elsif game_tick = '1' and game_state = RUNNING then
        if obstacle_x > -OBSTACLE_WIDTH then
          obstacle_x <= obstacle_x - speed_reg;
        else
          obstacle_x <= 640;
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
  begin
    if system_reset = '1' then
      player_x_reg <= to_unsigned(100, 32);
      player_y_reg <= to_unsigned(370, 32);
      bg_color_reg <= x"BCF";
      wb_ack_o     <= '0';
      velocity_y   <= 0;
      jump_request <= '0';
      game_over <= '0';
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

      -- Menü: btnC = Speed ändern, btnR = Start
      if game_state = MENU then
        if jump_i = '1' then
          if speed_reg = 5 then
            speed_reg <= 1;
          else
            speed_reg <= speed_reg + 1;
          end if;
        end if;

        if start_i = '1' then
          game_state     <= RUNNING;
          game_over      <= '0';
          score_reg      <= (others => '0');
          velocity_y     <= 0;
          jump_request   <= '0';
          game_reset_req <= '1';
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
              if to_integer(unsigned(wb_dat_i(3 downto 0))) < 1 then
                speed_reg <= 1;
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

        -- jump only from ground or block
        if (jump_request = '1' or jump_hold_i = '1') and
          (y_next = PLAYER_GROUND_Y or y_next = OBSTACLE_Y - PLAYER_SIZE) then
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

        -- land on top of obstacle
        if to_integer(player_x_reg(9 downto 0)) < obstacle_x + OBSTACLE_WIDTH and
          to_integer(player_x_reg(9 downto 0)) + PLAYER_SIZE > obstacle_x and
          velocity_y >= 0 and
          to_integer(player_y_reg(9 downto 0)) + PLAYER_SIZE <= OBSTACLE_Y and
          y_next + PLAYER_SIZE >= OBSTACLE_Y then

          y_next := OBSTACLE_Y - PLAYER_SIZE;
          v_next := 0;

        -- land on ground
        elsif y_next > PLAYER_GROUND_Y then
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
        color <= x"666";
      end if;

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
          color <= x"F00";
        else
          color <= x"0FF";
        end if;

      end if;
    
      -- moving obstacle block
      if (sx >= obstacle_x and sx < obstacle_x + OBSTACLE_WIDTH and
          sy >= OBSTACLE_Y and sy < OBSTACLE_Y + OBSTACLE_HEIGHT) then
        color <= x"F22";
      end if;

      -- simple triangle spike
      if (sx >= spike_x and sx < spike_x + SPIKE_WIDTH and
          sy >= SPIKE_Y and sy < SPIKE_Y + SPIKE_HEIGHT) then

        if sy >= SPIKE_Y + SPIKE_HEIGHT - (sx - spike_x) and
          sx < spike_x + SPIKE_WIDTH / 2 then
          color <= x"FF0";

        elsif sy >= SPIKE_Y + SPIKE_HEIGHT - ((spike_x + SPIKE_WIDTH - 1) - sx) and
              sx >= spike_x + SPIKE_WIDTH / 2 then
          color <= x"FF0";
        end if;

      end if;

      if game_state = MENU then
        color <= x"111";

        -- Speed bar background
        if sy >= 210 and sy < 230 and sx >= 220 and sx < 420 then
          color <= x"333";
        end if;

        -- Speed bar fill
        if sy >= 210 and sy < 230 and sx >= 220 and sx < 220 + speed_reg * 40 then
          color <= x"0F0";
        end if;

        -- player preview
        if sx >= 100 and sx < 130 and sy >= 370 and sy < 400 then
          color <= x"0FF";
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
