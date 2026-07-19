library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.game_pkg.all;

entity vga_controller is
  port (
    clk          : in    std_logic;
    system_reset : in    std_logic;
    wb_adr_i     : in    std_logic_vector(31 downto 0);
    wb_dat_i     : in    std_logic_vector(31 downto 0);
    wb_dat_o     : out   std_logic_vector(31 downto 0);
    wb_we_i      : in    std_logic;
    wb_sel_i     : in    std_logic_vector(3 downto 0);
    wb_stb_i     : in    std_logic;
    wb_cyc_i     : in    std_logic;
    wb_ack_o     : out   std_logic;
    pixel_clock  : in    std_logic;
    irq_vblank   : out   std_logic;
    vga_red      : out   std_logic_vector(3 downto 0);
    vga_green    : out   std_logic_vector(3 downto 0);
    vga_blue     : out   std_logic_vector(3 downto 0);
    h_sync       : out   std_logic;
    v_sync       : out   std_logic;
    btn_menu     : in    std_logic;
    jump_hold_i  : in    std_logic;
    btn_play     : in    std_logic
  );
end entity vga_controller;

architecture structural of vga_controller is

  -- Timing Generator Wires
  signal w_h_cnt       : integer range 0 to 799;
  signal w_v_cnt       : integer range 0 to 524;
  signal w_hsync_raw   : std_logic;
  signal w_vsync_raw   : std_logic;
  signal w_blank_raw   : std_logic;
  signal w_vblank_pix  : std_logic;

  -- Physics Engine Wires
  signal w_player_x      : unsigned(31 downto 0);
  signal w_player_y      : unsigned(31 downto 0);
  signal w_score         : unsigned(31 downto 0);
  signal w_speed_reg     : integer range 3 to 4;
  signal w_state_one_hot : std_logic_vector(3 downto 0);
  signal w_game_state    : std_logic_vector(1 downto 0);
  signal w_camera_x      : integer range 0 to 16000;
  signal w_camera_prog   : integer;
  signal w_game_over     : std_logic;

  -- MMIO Control Signals Interface Wires
  signal w_bg_color_reg   : std_logic_vector(11 downto 0);
  signal w_wb_reset_req   : std_logic;
  signal w_wb_speed_write : std_logic;
  signal w_wb_speed_val   : integer range 3 to 4;

begin

  -- 1. Instantiation: Clockwork Generation Module
  u_timing_gen : entity work.vga_timing_generator
    port map (
      clk          => clk,
      system_reset => system_reset,
      pixel_clock  => pixel_clock,
      h_cnt        => w_h_cnt,
      v_cnt        => w_v_cnt,
      hsync_raw    => w_hsync_raw,
      vsync_raw    => w_vsync_raw,
      blank_raw    => w_blank_raw,
      vblank_pix   => w_vblank_pix
    );

  -- 2. Instantiation: System Physics Processing Core
  u_physics_engine : entity work.game_physics_engine
    port map (
      clk                 => clk,
      system_reset        => system_reset,
      vblank_pix          => w_vblank_pix,
      btn_menu            => btn_menu,
      jump_hold_i         => jump_hold_i,
      btn_play            => btn_play,
      wb_reset_req        => w_wb_reset_req,
      wb_speed_write      => w_wb_speed_write,
      wb_speed_val        => w_wb_speed_val,
      player_x            => w_player_x,
      player_y            => w_player_y,
      score               => w_score,
      speed_reg_out       => w_speed_reg,
      game_state_one_hot  => w_state_one_hot,
      game_state_out      => w_game_state,
      camera_x_out        => w_camera_x,
      camera_progress     => w_camera_prog,
      game_over_out       => w_game_over,
      irq_vblank          => irq_vblank
    );

  -- 3. Instantiation: Wishbone MMIO Target Control Register Bridge
  u_mmio_bridge : entity work.wishbone_mmio_interface
    port map (
      clk                => clk,
      system_reset       => system_reset,
      wb_adr_i           => wb_adr_i,
      wb_dat_i           => wb_dat_i,
      wb_dat_o           => wb_dat_o,
      wb_we_i            => wb_we_i,
      wb_sel_i           => wb_sel_i,
      wb_stb_i           => wb_stb_i,
      wb_cyc_i           => wb_cyc_i,
      wb_ack_o           => wb_ack_o,
      player_x           => std_logic_vector(w_player_x),
      player_y           => std_logic_vector(w_player_y),
      score              => std_logic_vector(w_score),
      speed_reg          => w_speed_reg,
      game_state_one_hot => w_state_one_hot,
      bg_color_reg       => w_bg_color_reg,
      wb_reset_req       => w_wb_reset_req,
      wb_speed_write     => w_wb_speed_write,
      wb_speed_val       => w_wb_speed_val
    );

  -- 4. Instantiation: Math Color Painter Render Engine
  u_pixel_pipeline : entity work.vga_pixel_pipeline
    port map (
      clk             => clk,
      pixel_clock     => pixel_clock,
      h_cnt           => w_h_cnt,
      v_cnt           => w_v_cnt,
      hsync_raw       => w_hsync_raw,
      vsync_raw       => w_vsync_raw,
      blank_raw       => w_blank_raw,
      player_x        => w_player_x,
      player_y        => w_player_y,
      camera_x        => w_camera_x,
      camera_progress => w_camera_prog,
      game_state_out  => w_game_state,
      speed_reg       => w_speed_reg,
      game_over       => w_game_over,
      bg_color_reg    => w_bg_color_reg,
      vga_red         => vga_red,
      vga_green       => vga_green,
      vga_blue        => vga_blue,
      h_sync          => h_sync,
      v_sync          => v_sync
    );

end architecture structural;
