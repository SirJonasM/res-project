library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity pixel_clock is
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;
    pixel_en : out std_logic -- Changed from clk_out
  );
end entity pixel_clock;

architecture behavioral of pixel_clock is
  constant pixel_period : integer := 4;
  signal   counter      : integer := 3; -- Initialize properly for count-down
begin

  process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1') then
        counter  <= pixel_period - 1;
        pixel_en <= '0';
      elsif (counter = 0) then
        counter  <= pixel_period - 1;
        pixel_en <= '1'; -- Strobe active for exactly 1 master clock cycle
      else
        counter  <= counter - 1;
        pixel_en <= '0';
      end if;
    end if;
  end process;

end architecture behavioral;
