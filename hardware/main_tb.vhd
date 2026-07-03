library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  -- CRITICAL: Add these context references for terminal output mapping
  use std.textio.all;
  use ieee.std_logic_textio.all;

entity main_tb is
-- Testbenches do not have ports
end entity main_tb;

architecture behavioral of main_tb is

  component main is
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
      vga_red_0   : out   std_logic;
      vga_red_1   : out   std_logic;
      vga_red_2   : out   std_logic;
      vga_red_3   : out   std_logic;
      vga_blue_0  : out   std_logic;
      vga_blue_1  : out   std_logic;
      vga_blue_2  : out   std_logic;
      vga_blue_3  : out   std_logic;
      vga_green_0 : out   std_logic;
      vga_green_1 : out   std_logic;
      vga_green_2 : out   std_logic;
      vga_green_3 : out   std_logic;
      btn_c       : in    std_logic;
      h_sync      : out   std_logic;
      v_sync      : out   std_logic
    );
  end component main;

  -- Testbench Signals
  signal clk_tb             : std_logic := '0';
  signal leds_tb            : std_logic_vector(15 downto 0);
  signal rsrx_tb            : std_logic := '1'; -- Default UART idle state is High
  signal rstx_tb            : std_logic;
  signal vga_r              : std_logic_vector(3 downto 0);
  signal vga_g              : std_logic_vector(3 downto 0);
  signal vga_b              : std_logic_vector(3 downto 0);
  signal hsync_tb, vsync_tb : std_logic;
  signal btn_c_tb           : std_logic;

  constant clk_period : time := 10 ns;

  -- 1 / 115200 Baud Rate = 8.6805 microseconds per bit timing width
  constant bit_period : time := 8.68 us;

begin

  -- Instantiate Device Under Test
  dut : component main
    port map (
      clk         => clk_tb,
      led0        => leds_tb(0),
      led1        => leds_tb(1),
      led2        => leds_tb(2),
      led3        => leds_tb(3),
      led4        => leds_tb(4),
      led5        => leds_tb(5),
      led6        => leds_tb(6),
      led7        => leds_tb(7),
      led8        => leds_tb(8),
      led9        => leds_tb(9),
      led10       => leds_tb(10),
      led11       => leds_tb(11),
      led12       => leds_tb(12),
      led13       => leds_tb(13),
      led14       => leds_tb(14),
      led15       => leds_tb(15),
      btn_c       => btn_c_tb,
      rs_rx      => rsrx_tb,
      rs_tx       => rstx_tb,
      vga_red_0   => vga_r(0),
      vga_red_1   => vga_r(1),
      vga_red_2   => vga_r(2),
      vga_red_3   => vga_r(3),
      vga_green_0 => vga_g(0),
      vga_green_1 => vga_g(1),
      vga_green_2 => vga_g(2),
      vga_green_3 => vga_g(3),
      vga_blue_0  => vga_b(0),
      vga_blue_1  => vga_b(1),
      vga_blue_2  => vga_b(2),
      vga_blue_3  => vga_b(3),
      h_sync      => hsync_tb,
      v_sync      => vsync_tb
    );

  -- Clock Generator
  clk_process : process is
  begin

    while true loop

      clk_tb <= '0';
      wait for clk_period / 2;
      clk_tb <= '1';
      wait for clk_period / 2;

    end loop;

  end process clk_process;

  -- =========================================================================
  -- SIMULATION TERMINAL PRINT LOG ENGINE (TIO SETUP)
  -- =========================================================================
  uart_consoled_monitor : process is

    -- Timing constants extracted directly from your UART_Sender specification
    constant baud_limit   : integer := 868;
    constant tick_period  : time    := 10 ns;
    constant bit_duration : time    := baud_limit * tick_period; -- 8.68 us

    variable rx_byte_reg : std_logic_vector(7 downto 0);
    variable text_line   : line;

  begin

    while true loop

      -- 1. Look for the falling edge of RsTx (The Start Bit)
      wait until falling_edge(rstx_tb);

      -- 2. Step forward by 1.5 Bit windows to skip the start bit
      --    and align perfectly with the center point of Data Bit 0
      wait for bit_duration + (bit_duration / 2);

      -- 3. Sequentially sample all 8 bits at their stable centers
      for i in 0 to 7 loop

        rx_byte_reg(i) := rstx_tb;
        wait for bit_duration;

      end loop;

      -- 4. Cast the raw sampled logic bits to an ASCII character type
      --    and flush the string buffer line instantly to your stdout shell
      write(text_line, character'val(to_integer(unsigned(rx_byte_reg))));
      writeline(output, text_line);

    end loop;

  end process uart_consoled_monitor;

end architecture behavioral;
