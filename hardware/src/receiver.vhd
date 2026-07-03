library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity uart_receiver is
  port (
    clk      : in    std_logic;
    data_in  : in    std_logic;
    rx_data  : out   std_logic_vector(7 downto 0);
    rx_valid : out   std_logic
  );
end entity uart_receiver;

architecture behavioral of uart_receiver is

  constant baud_period      : integer := 868;
  constant baud_half_period : integer := 434;

  type state_type is (idle, wait_half_period, read_package, act);

  signal state : state_type := idle;

  signal data_sync : std_logic_vector(1 downto 0) := "11";

  signal wait_counter   : integer                      := baud_half_period;
  signal period_counter : integer                      := baud_period;
  signal data           : std_logic_vector(9 downto 0) := "0000000000";
  signal bit_counter    : integer range 0 to 11        := 0;

begin

  process (clk) is
  begin

    if rising_edge(clk) then
      data_sync <= data_sync(0) & data_in;
      rx_valid  <= '0'; -- Default to low every clock cycle unless explicit in ACT

      case state is

        when idle =>

          if (data_sync = "10") then
            bit_counter    <= 0;
            period_counter <= 0;
            wait_counter   <= baud_half_period - 1;
            state          <= wait_half_period;
          end if;

        when wait_half_period =>

          if (wait_counter = 0) then
            state <= read_package;
          else
            wait_counter <= wait_counter - 1;
          end if;

        when read_package =>

          if (period_counter = 0) then
            period_counter    <= baud_period - 1;
            data(bit_counter) <= data_sync(1);
            if (bit_counter = 9) then
              state <= act;
            else
              bit_counter <= bit_counter + 1;
            end if;
          else
            period_counter <= period_counter - 1;
          end if;

        when act =>

          -- Output the clean ASCII byte and pulse valid
          rx_data  <= data(8 downto 1);
          rx_valid <= '1';
          state    <= idle;

        when others =>

          state <= idle;

      end case;

    end if;

  end process;

end architecture behavioral;
