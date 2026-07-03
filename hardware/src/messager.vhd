library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity uart_sender is
  port (
    clk      : in    std_logic;
    tx_start : in    std_logic;
    tx_data  : in    std_logic_vector(7 downto 0);
    tx_out   : out   std_logic := '1';
    tx_busy  : out   std_logic := '0'
  );
end entity uart_sender;

architecture behavioral of uart_sender is

  constant baud_period : integer := 868;

  type state_type is (idle, start_bit, data_bits, stop_bit);

  signal state : state_type := idle;

  signal period_counter : integer                      := baud_period;
  signal data_buffer    : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_counter    : integer range 0 to 7         := 0;

begin

  process (clk) is
  begin

    if rising_edge(clk) then

      case state is

        when idle =>

          tx_out  <= '1';
          tx_busy <= '0';
          if (tx_start = '1') then
            data_buffer    <= tx_data;
            period_counter <= baud_period - 1;
            tx_busy        <= '1';
            tx_out         <= '0';                         -- Pull low for Start Bit
            state          <= start_bit;
          end if;

        when start_bit =>

          if (period_counter = 0) then
            period_counter <= baud_period - 1;
            bit_counter    <= 0;
            tx_out         <= data_buffer(0);              -- Send LSB first
            state          <= data_bits;
          else
            period_counter <= period_counter - 1;
          end if;

        when data_bits =>

          if (period_counter = 0) then
            period_counter <= baud_period - 1;
            if (bit_counter = 7) then
              tx_out <= '1';                               -- Pull high for Stop Bit
              state  <= stop_bit;
            else
              bit_counter <= bit_counter + 1;
              tx_out      <= data_buffer(bit_counter + 1);
            end if;
          else
            period_counter <= period_counter - 1;
          end if;

        when stop_bit =>

          if (period_counter = 0) then
            tx_busy <= '0';
            state   <= idle;
          else
            period_counter <= period_counter - 1;
          end if;

      end case;

    end if;

  end process;

end architecture behavioral;
