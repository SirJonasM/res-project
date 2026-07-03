library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library neorv32;
  use neorv32.neorv32_package.all;

entity trap_uart_monitor is
  generic (
    clk_freq  : integer  := 100000000; -- 100 MHz System Clock
    baud_rate : positive := 115200
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Inputs from CPU Trace Port
    trace_i : in    trace_port_t;

    -- Physical UART Lines
    uart_tx_mux_o : out   std_logic; -- Trap UART Tx output
    active_o      : out   std_logic  -- High when taking control of UART
  );
end entity trap_uart_monitor;

architecture rtl of trap_uart_monitor is

  -- Baud rate clock divider
  constant bit_period : integer                           := clk_freq / baud_rate;
  signal   clk_cnt    : integer range 0 to bit_period - 1 := 0;
  signal   baud_tick  : std_logic                         := '0';

  -- FSM States

  type state_t is (idle, load_char, send_start, send_data, send_stop, next_char);

  signal state : state_t := idle;

  -- String layout: "PC=XXXXXXXX INSN=XXXXXXXX ADDR=XXXXXXXX CSR=XXXXXXXX\r\n"
  -- Total characters = 3 + 8 + 6 + 8 + 6 + 8 + 5 + 8 + 2 = 54 characters
  constant buffer_size : positive := 54;

  type char_buffer_t is array (0 to buffer_size - 1) of std_logic_vector(7 downto 0);

  signal tx_buffer : char_buffer_t := (others => (others => '0'));

  signal char_idx : integer range 0 to buffer_size := 0;
  signal tx_reg   : std_logic_vector(7 downto 0)   := (others => '1');
  signal bit_idx  : integer range 0 to 7           := 0;
  signal tx_out   : std_logic                      := '1';

  -- Helper function to convert 4-bit nibble to ASCII hex character

  function nibble_to_ascii (
    nibble : std_logic_vector(3 downto 0)
  ) return std_logic_vector is
  begin

    if (unsigned(nibble) < 10) then
      return std_logic_vector(unsigned(nibble) + x"30"); -- '0' - '9'
    else
      return std_logic_vector(unsigned(nibble) + x"37"); -- 'A' - 'F'
    end if;

  end function nibble_to_ascii;

begin

  uart_tx_mux_o <= tx_out;
  active_o      <= '1' when (state /= idle) else
                   '0';

  -- Baud Tick Generator
  process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (clk_cnt = bit_period - 1) then
        clk_cnt   <= 0;
        baud_tick <= '1';
      else
        clk_cnt   <= clk_cnt + 1;
        baud_tick <= '0';
      end if;
    end if;

  end process;

  -- Control FSM
  -- Control FSM
  process (clk_i) is

    variable v_pc   : std_logic_vector(31 downto 0);
    variable v_insn : std_logic_vector(31 downto 0);
    variable v_addr : std_logic_vector(31 downto 0);
    variable v_csr  : std_logic_vector(31 downto 0);

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state    <= idle;
        tx_out   <= '1';
        char_idx <= 0;
      else

        case state is

          when idle =>

            tx_out <= '1';
            -- Detect edge of trap condition
            if (trace_i.trap = '1' and trace_i.valid = '1') then
              -- Safeguard typecasts from std_ulogic_vector to std_logic_vector
              v_pc   := std_logic_vector(trace_i.pc_rdata);
              v_insn := std_logic_vector(trace_i.insn);
              v_addr := std_logic_vector(trace_i.mem_addr);
              v_csr  := std_logic_vector(trace_i.csr_rdata);

              -- [0-2] "PC="
              tx_buffer(0) <= x"50";                                  -- 'P'
              tx_buffer(1) <= x"43";                                  -- 'C'
              tx_buffer(2) <= x"3D";                                  -- '='
              -- [3-10] PC Hex data
              tx_buffer(3)  <= nibble_to_ascii(v_pc(31 downto 28));
              tx_buffer(4)  <= nibble_to_ascii(v_pc(27 downto 24));
              tx_buffer(5)  <= nibble_to_ascii(v_pc(23 downto 20));
              tx_buffer(6)  <= nibble_to_ascii(v_pc(19 downto 16));
              tx_buffer(7)  <= nibble_to_ascii(v_pc(15 downto 12));
              tx_buffer(8)  <= nibble_to_ascii(v_pc(11 downto  8));
              tx_buffer(9)  <= nibble_to_ascii(v_pc( 7 downto  4));
              tx_buffer(10) <= nibble_to_ascii(v_pc( 3 downto  0));

              -- [11-16] " INSN="
              tx_buffer(11) <= x"20";                                 -- ' '
              tx_buffer(12) <= x"49";                                 -- 'I'
              tx_buffer(13) <= x"4E";                                 -- 'N'
              tx_buffer(14) <= x"53";                                 -- 'S'
              tx_buffer(15) <= x"4E";                                 -- 'N'
              tx_buffer(16) <= x"3D";                                 -- '='
              -- [17-24] INSN Hex data
              tx_buffer(17) <= nibble_to_ascii(v_insn(31 downto 28));
              tx_buffer(18) <= nibble_to_ascii(v_insn(27 downto 24));
              tx_buffer(19) <= nibble_to_ascii(v_insn(23 downto 20));
              tx_buffer(20) <= nibble_to_ascii(v_insn(19 downto 16));
              tx_buffer(21) <= nibble_to_ascii(v_insn(15 downto 12));
              tx_buffer(22) <= nibble_to_ascii(v_insn(11 downto  8));
              tx_buffer(23) <= nibble_to_ascii(v_insn( 7 downto  4));
              tx_buffer(24) <= nibble_to_ascii(v_insn( 3 downto  0));

              -- [25-30] " ADDR="
              tx_buffer(25) <= x"20";                                 -- ' '
              tx_buffer(26) <= x"41";                                 -- 'A'
              tx_buffer(27) <= x"44";                                 -- 'D'
              tx_buffer(28) <= x"44";                                 -- 'D'
              tx_buffer(29) <= x"52";                                 -- 'R'
              tx_buffer(30) <= x"3D";                                 -- '='
              -- [31-38] ADDR Hex data
              tx_buffer(31) <= nibble_to_ascii(v_addr(31 downto 28));
              tx_buffer(32) <= nibble_to_ascii(v_addr(27 downto 24));
              tx_buffer(33) <= nibble_to_ascii(v_addr(23 downto 20));
              tx_buffer(34) <= nibble_to_ascii(v_addr(19 downto 16));
              tx_buffer(35) <= nibble_to_ascii(v_addr(15 downto 12));
              tx_buffer(36) <= nibble_to_ascii(v_addr(11 downto  8));
              tx_buffer(37) <= nibble_to_ascii(v_addr( 7 downto  4));
              tx_buffer(38) <= nibble_to_ascii(v_addr( 3 downto  0));

              -- [25-30] " ADDR="
              tx_buffer(39) <= x"20";                                 -- ' '
              tx_buffer(40) <= x"43";                                 -- 'C'
              tx_buffer(41) <= x"53";                                 -- 'S'
              tx_buffer(42) <= x"52";                                 -- 'R'
              tx_buffer(43) <= x"3D";                                 -- '='

              tx_buffer(44) <= nibble_to_ascii(v_csr(31 downto 28));
              tx_buffer(45) <= nibble_to_ascii(v_csr(27 downto 24));
              tx_buffer(46) <= nibble_to_ascii(v_csr(23 downto 20));
              tx_buffer(47) <= nibble_to_ascii(v_csr(19 downto 16));
              tx_buffer(48) <= nibble_to_ascii(v_csr(15 downto 12));
              tx_buffer(49) <= nibble_to_ascii(v_csr(11 downto  8));
              tx_buffer(50) <= nibble_to_ascii(v_csr( 7 downto  4));
              tx_buffer(51) <= nibble_to_ascii(v_csr( 3 downto  0));
              -- [39-40] Newline termination
              tx_buffer(52) <= x"0D";                                 -- Carriage Return '\r'
              tx_buffer(53) <= x"0A";                                 -- Line Feed '\n'

              char_idx <= 0;
              state    <= load_char;
            end if;

          when load_char =>

            if (char_idx < buffer_size) then
              tx_reg <= tx_buffer(char_idx);
              state  <= send_start;
            else
              state <= idle;
            end if;

          when send_start =>

            if (baud_tick = '1') then
              tx_out  <= '0';                                         -- Start Bit
              bit_idx <= 0;
              state   <= send_data;
            end if;

          when send_data =>

            if (baud_tick = '1') then
              tx_out <= tx_reg(bit_idx);
              if (bit_idx = 7) then
                state <= send_stop;
              else
                bit_idx <= bit_idx + 1;
              end if;
            end if;

          when send_stop =>

            if (baud_tick = '1') then
              tx_out <= '1';                                          -- Stop Bit
              state  <= next_char;
            end if;

          when next_char =>

            if (baud_tick = '1') then
              char_idx <= char_idx + 1;
              state    <= load_char;
            end if;

          when others =>

            state <= idle;

        end case;

      end if;
    end if;

  end process;

end architecture rtl;
