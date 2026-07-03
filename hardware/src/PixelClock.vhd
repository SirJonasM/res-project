library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity pixel_clock is
  port (
    clk     : in    std_logic;
    reset   : in    std_logic;
    clk_out : out   std_logic
  );
end entity pixel_clock;

architecture behavioral of pixel_clock is

  constant pixel_period : integer := 4;
  signal   counter      : integer := 4;

begin

  process (clk, reset) is
  begin

    if rising_edge(clk) then
      if (reset = '1') then
        counter <= pixel_period - 1;
        clk_out <= '0';
      elsif (counter = 0) then
        counter <= pixel_period - 1;
        clk_out <= '1';
      else
        counter <= counter - 1;
        clk_out <= '0';
      end if;
    end if;

  end process;

end architecture behavioral;
