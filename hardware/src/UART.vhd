library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library neorv32;
  use work.fifo;
  use work.uart_receiver;
  use work.uart_sender;

entity uart is
  port (
    clk   : in    std_logic;
    reset : in    std_logic;

    -- CPU Bus Register Mapping Interface
    reg_addr  : in    std_logic;
    reg_we    : in    std_logic;
    reg_re    : in    std_logic;
    reg_wdata : in    std_logic_vector(7 downto 0);
    reg_rdata : out   std_logic_vector(7 downto 0);

    -- Hardware Pins
    rsrx : in    std_logic;
    rstx : out   std_logic;

    -- ADD THIS: Edge-triggered interrupt signal output
    uart_rx_irq_o : out   std_logic
  );
end entity uart;

architecture structural of uart is

  -- Internal Receiver Signal Links
  signal rx_byte       : std_logic_vector(7 downto 0);
  signal rx_valid      : std_logic;
  signal rx_fifo_empty : std_logic;
  signal rx_fifo_full  : std_logic;
  signal rx_fifo_rd    : std_logic;
  signal rx_fifo_out   : std_logic_vector(7 downto 0);

  -- Internal Sender Signal Links
  signal tx_start      : std_logic := '0';
  signal tx_busy       : std_logic;
  signal tx_fifo_empty : std_logic;
  signal tx_fifo_full  : std_logic;
  signal tx_fifo_rd    : std_logic := '0';
  signal tx_fifo_out   : std_logic_vector(7 downto 0);
  signal uart_wr_en    : std_logic;

  -- CPU Read Demux Helper
  signal status_vector : std_logic_vector(7 downto 0);

  signal rx_fifo_empty_p1 : std_logic := '1'; -- Holds previous cycle value

begin

  uart_wr_en <= reg_we and (not reg_addr);
  -- Status Mapping layout assembly:
  -- Bit 0: Data Available to Read | Bit 1: Transmission Buffer Maxed Out
  status_vector <= "000000" & tx_fifo_full & (not rx_fifo_empty);

  -- Custom receiver logic from step 1
  rcvr_core : entity uart_receiver
    port map (
      clk      => clk,
      data_in  => rsrx,
      rx_data  => rx_byte,
      rx_valid => rx_valid
    );

  -- RX Storage Queue Buffer
  rx_buffer : entity fifo
    port map (
      clk     => clk,
      reset   => reset,
      wr_en   => rx_valid,
      wr_data => rx_byte,
      rd_en   => rx_fifo_rd,
      rd_data => rx_fifo_out,
      empty   => rx_fifo_empty,
      full    => rx_fifo_full
    );

  -- TX Storage Queue Buffer
  tx_buffer : entity fifo
    port map (
      clk     => clk,
      reset   => reset,
      wr_en   => uart_wr_en,
      wr_data => reg_wdata,
      rd_en   => tx_fifo_rd,
      rd_data => tx_fifo_out,
      empty   => tx_fifo_empty,
      full    => tx_fifo_full
    );

  -- Custom transmitter logic from step 1
  sndr_core : entity uart_sender
    port map (
      clk      => clk,
      tx_start => tx_start,
      tx_data  => tx_fifo_out,
      tx_out   => rstx,
      tx_busy  => tx_busy
    );

  -- =========================================================================
  -- Autonomous Hardware Orchestration & MMIO Logic
  -- =========================================================================
  -- Detect when the FIFO goes from empty to holding data
  process (clk) is
  begin

    if rising_edge(clk) then
      if (reset = '1') then
        rx_fifo_empty_p1 <= '1';
        uart_rx_irq_o    <= '0';
      else
        rx_fifo_empty_p1 <= rx_fifo_empty;

        -- If it WAS empty last cycle, but is NOT empty this cycle, fire a pulse!
        if (rx_fifo_empty_p1 = '1' and rx_fifo_empty = '0') then
          uart_rx_irq_o <= '1';
        else
          uart_rx_irq_o <= '0';
        end if;
      end if;
    end if;

  end process;

  -- Automatic TX Spooler: Pulls bytes from TX FIFO out to sender automatically
  process (clk) is

    variable tx_active : std_logic := '0';

  begin

    if rising_edge(clk) then
      if (reset = '1') then
        tx_start   <= '0';
        tx_fifo_rd <= '0';
        tx_active  := '0';
      else
        tx_start   <= '0';
        tx_fifo_rd <= '0';

        if (tx_active = '0') then
          -- If the buffer holds elements and physical channel line is clear
          if (tx_fifo_empty = '0' and tx_busy = '0') then
            tx_fifo_rd <= '1';                            -- Pop item out of data queue array
            tx_start   <= '1';                            -- Strobe launch execution signal
            tx_active  := '1';
          end if;
        else
          if (tx_busy = '1') then
            tx_active := '0';                             -- Clear latch handshaking guard
          end if;
        end if;
      end if;
    end if;

  end process;

  -- CPU Bus Address Decoding Matrix Selector
  rx_fifo_rd <= reg_re when (reg_addr = '0') else
                '0'; -- Pop RX FIFO on CPU Read to Address 0

  process (reg_addr, rx_fifo_out, status_vector) is
  begin

    if (reg_addr = '0') then
      reg_rdata <= rx_fifo_out;
    else
      reg_rdata <= status_vector;
    end if;

  end process;

end architecture structural;
