library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library lib;

library neorv32;
  use neorv32.neorv32_package.all;
  use neorv32.neorv32_top;

entity main is
  port (
    clk         : in    std_logic;
    led0        : out   std_logic;
    led1        : out   std_logic;
    led2        : out   std_logic;
    led3        : out   std_logic;
    led4        : out   std_logic;
    led5        : out   std_logic;
    led6        : out   std_logic;
    led7        : out   std_logic;
    led8        : out   std_logic;
    led9        : out   std_logic;
    led10       : out   std_logic;
    led11       : out   std_logic;
    led12       : out   std_logic;
    led13       : out   std_logic;
    led14       : out   std_logic;
    led15       : out   std_logic;
    rs_rx       : in    std_logic;
    rs_tx       : out   std_logic;
    btn_c       : in    std_logic
  );
end entity main;

architecture structural of main is

  constant interrupt_count : positive := 2;

  -- Hardware Register to hold the LED state (0 = Off, 1 = On)

  signal interrupt_pulse : std_logic;
  signal led_reg         : std_logic_vector(15 downto 0);
  signal led_rdata       : std_logic_vector(31 downto 0);
  signal irq_rdata       : std_logic_vector(31 downto 0);
  signal button_pulse    : std_logic                                      := '0';
  signal uart_pulse      : std_logic                                      := '0';
  signal irq_pulses      : std_logic_vector(interrupt_count - 1 downto 0) := (others => '0');
  signal uart_rdata      : std_logic_vector(31 downto 0);
  signal led_ack         : std_logic                                      := '0';
  signal irq_ack         : std_logic                                      := '0';

  -- Reset System (NEORV32 rstn_i is Active-LOW)
  signal system_reset   : std_logic            := '1';
  signal system_reset_n : std_logic            := '0';
  signal reset_cnt      : unsigned(3 downto 0) := (others => '0');

  -- Clocking Trackers
  signal pixel_clock : std_logic := '0';

  -- System Core Bus Fabric Interconnect Signals
  signal cpu_bram_addr  : std_logic_vector(31 downto 0);
  signal cpu_bram_wdata : std_logic_vector(31 downto 0);
  signal cpu_bram_rdata : std_logic_vector(31 downto 0);
  signal cpu_bram_ack   : std_logic := '0';


  -- Signals to interface the Trap Monitor
  signal trap_uart_tx : std_logic;
  signal trap_active  : std_logic;
  signal core_uart_tx : std_logic; -- Captures output of normal UART core
  signal uart_ack     : std_logic := '0';


  -- Flattened XBUS Wires
  signal xbus_adr_sig       : std_ulogic_vector(31 downto 0);
  signal xbus_dat_wdata_sig : std_ulogic_vector(31 downto 0);
  signal xbus_dat_rdata_sig : std_ulogic_vector(31 downto 0);
  signal xbus_we_sig        : std_ulogic;
  signal xbus_sel_sig       : std_ulogic_vector(3 downto 0);
  signal xbus_stb_sig       : std_ulogic;
  signal xbus_cyc_sig       : std_ulogic;
  signal xbus_ack_sig       : std_ulogic;
  signal xbus_err_sig       : std_ulogic;
  signal trace              : trace_port_t;

  signal sel_rom  : std_logic;
  signal sel_vram : std_logic;
  signal sel_uart : std_logic;
  signal sel_led  : std_logic;
  signal sel_irq  : std_logic;

begin

  irq_pulses <= (uart_pulse, button_pulse);

  sel_rom  <= '1' when xbus_adr_sig(31 downto 28) = x"0" else
              '0';
  sel_vram <= '1' when xbus_adr_sig(31 downto 28) = x"1" else
              '0';
  sel_uart <= '1' when xbus_adr_sig(31 downto 28) = x"2" else
              '0';
  sel_led  <= '1' when xbus_adr_sig(31 downto 28) = x"3" else
              '0';
  sel_irq  <= '1' when xbus_adr_sig(31 downto 28) = x"8" else
              '0';

  led0  <= led_reg(0);
  led1  <= led_reg(1);
  led2  <= led_reg(2);
  led3  <= led_reg(3);
  led4  <= led_reg(4);
  led5  <= led_reg(5);
  led6  <= led_reg(6);
  led7  <= led_reg(7);
  led8  <= led_reg(8);
  led9  <= led_reg(9);
  led10 <= led_reg(10);
  led11 <= led_reg(11);
  led12 <= led_reg(12);
  led13 <= trace.valid;
  led14 <= trace.halt;
  led15 <= trace.trap;

  -- Power-on Reset Logic
  reset_proc : process (clk) is
  begin

    if rising_edge(clk) then
      if (reset_cnt < 10) then
        system_reset   <= '1';
        system_reset_n <= '0';
        reset_cnt      <= reset_cnt + 1;
      else
        system_reset   <= '0';
        system_reset_n <= '1';
      end if;
    end if;

  end process reset_proc;

  -- =========================================================================
  -- NEORV32 Unified Flat Bus Interface Assignments (Strict Specification Match)
  -- =========================================================================
  -- Cast incoming types to local variables; values remain stable throughout the cycle
  cpu_bram_addr  <= std_logic_vector(xbus_adr_sig);
  cpu_bram_wdata <= std_logic_vector(xbus_dat_wdata_sig);
  -- Instance of your new helper entity
  button_debounce_inst : entity lib.button_pulse_detector
    port map (
      clk_i   => clk,
      rstn_i  => system_reset_n,
      btn_i   => btn_c,
      pulse_o => button_pulse
    );

  -- =========================================================================
  -- Structural Fabric Interconnect Wiring Map
  -- =========================================================================
  cpu_core : entity neorv32.neorv32_top
    generic map (
      clock_frequency  => 100000000,
      boot_mode_select => 1,
      boot_addr_custom => x"00000000",
      xbus_en          => true,
      io_tracer_en     => true,
      io_wdt_en        => true
    )
    port map (
      clk_i  => clk,
      rstn_i => system_reset_n,

      xbus_adr_o => xbus_adr_sig,
      xbus_dat_o => xbus_dat_wdata_sig,
      xbus_dat_i => xbus_dat_rdata_sig,
      xbus_we_o  => xbus_we_sig,
      xbus_sel_o => xbus_sel_sig,
      xbus_stb_o => xbus_stb_sig,
      xbus_cyc_o => xbus_cyc_sig,
      xbus_ack_i => xbus_ack_sig,
      xbus_err_i => xbus_err_sig,

      irq_mei_i    => interrupt_pulse,
      trace_cpu0_o => trace
    );

  boot_rom_ram : entity lib.cpu_bram
    generic map (
      mem_size_bytes => 32768,
      hex_file_name  => "firmware.hex"
    )
    port map (
      clk_i    => clk,
      rst_i    => system_reset,
      wb_adr_i => cpu_bram_addr,
      wb_dat_i => cpu_bram_wdata,
      wb_dat_o => cpu_bram_rdata,
      wb_we_i  => xbus_we_sig,
      wb_sel_i => std_logic_vector(xbus_sel_sig),
      wb_stb_i => xbus_stb_sig and sel_rom,
      wb_cyc_i => xbus_cyc_sig and sel_rom,
      wb_ack_o => cpu_bram_ack
    );

  pixel_clock_unit : entity lib.pixel_clock
    port map (
      clk     => clk,
      reset   => system_reset,
      clk_out => pixel_clock
    );


  uart_sub_peripheral : entity lib.uart_wb
    port map (
      clk      => clk,
      reset    => system_reset,
      wb_adr_i => std_logic_vector(xbus_adr_sig),
      wb_dat_i => std_logic_vector(xbus_dat_wdata_sig),
      wb_dat_o => uart_rdata,

      wb_we_i  => xbus_we_sig,
      wb_sel_i => std_logic_vector(xbus_sel_sig),

      wb_stb_i => xbus_stb_sig and sel_uart,
      wb_cyc_i => xbus_cyc_sig and sel_uart,

      wb_ack_o      => uart_ack,
      rsrx          => rs_rx,
      rstx          => core_uart_tx,
      uart_rx_irq_o => uart_pulse
    );

  trap_monitor_unit : entity lib.trap_uart_monitor
    generic map (
      clk_freq  => 100000000,
      baud_rate => 115200
    )
    port map (
      clk_i         => clk,
      rst_i         => system_reset,
      trace_i       => trace,
      uart_tx_mux_o => trap_uart_tx,
      active_o      => trap_active
    );

  rs_tx <= trap_uart_tx when (trap_active = '1') else
           core_uart_tx;

  irq : entity lib.irq_peripheral
    generic map (
      num_irqs => INTERRUPT_COUNT
    )
    port map (
      clk   => clk,
      reset => system_reset,

      wb_adr_i => std_logic_vector(xbus_adr_sig),
      wb_dat_i => std_logic_vector(xbus_dat_wdata_sig),
      wb_dat_o => irq_rdata,

      wb_we_i  => xbus_we_sig,
      wb_sel_i => std_logic_vector(xbus_sel_sig),

      wb_stb_i => xbus_stb_sig and sel_irq,
      wb_cyc_i => xbus_cyc_sig and sel_irq,

      wb_ack_o     => irq_ack,
      irq_pulses_i => irq_pulses,
      cpu_mext_o   => interrupt_pulse
    );

  leds : entity lib.led_peripheral
    port map (
      clk   => clk,
      reset => system_reset,

      wb_adr_i => std_logic_vector(xbus_adr_sig),
      wb_dat_i => std_logic_vector(xbus_dat_wdata_sig),
      wb_dat_o => led_rdata,

      wb_we_i  => xbus_we_sig,
      wb_sel_i => std_logic_vector(xbus_sel_sig),

      wb_stb_i => xbus_stb_sig and sel_led,
      wb_cyc_i => xbus_cyc_sig and sel_led,

      wb_ack_o => led_ack,

      leds_o => led_reg
    );

  -- =========================================================================
  -- MMIO Address Decoder Crossbar Process (Strict 2-Cycle Protocol Engine)
  -- =========================================================================
  process (all) is
  begin

    xbus_ack_sig       <= '0';
    xbus_err_sig       <= '0';
    xbus_dat_rdata_sig <= (others => '0');

    case xbus_adr_sig(31 downto 28) is

      -- bram for cpu
      when x"0" =>

        xbus_ack_sig       <= cpu_bram_ack;
        xbus_dat_rdata_sig <= cpu_bram_rdata;

      -- uart peripheral
      when x"2" =>

        xbus_ack_sig       <= uart_ack;
        xbus_dat_rdata_sig <= uart_rdata;

      -- led peripheral
      when x"3" =>

        xbus_ack_sig       <= led_ack;
        xbus_dat_rdata_sig <= led_rdata;

      -- Interrupt controler
      when x"8" =>

        xbus_ack_sig       <= irq_ack;
        xbus_dat_rdata_sig <= irq_rdata;

      when x"F" =>

        xbus_ack_sig       <= '0';
        xbus_err_sig       <= '0';
        xbus_dat_rdata_sig <= (others => '0');

      when others =>

        xbus_ack_sig <= '1';
        xbus_err_sig <= '1';

    end case;

  end process;

end architecture structural;
