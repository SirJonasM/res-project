library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity led_peripheral is
  port (
    clk   : in    std_logic;
    reset : in    std_logic;

    wb_adr_i : in    std_logic_vector(31 downto 0);
    wb_dat_i : in    std_logic_vector(31 downto 0);
    wb_dat_o : out   std_logic_vector(31 downto 0);

    wb_we_i  : in    std_logic;
    wb_sel_i : in    std_logic_vector(3 downto 0);
    wb_stb_i : in    std_logic;
    wb_cyc_i : in    std_logic;
    wb_ack_o : out   std_logic;

    leds_o : out   std_logic_vector(15 downto 0)
  );
end entity led_peripheral;

architecture rtl of led_peripheral is

  signal leds    : std_logic_vector(15 downto 0);
  signal ack_reg : std_logic;

begin

  leds_o <= leds;

  process (clk) is
  begin

    if rising_edge(clk) then
      ack_reg <= '0';

      if (reset = '1') then
        leds <= (others => '0');
      elsif (wb_cyc_i = '1' and wb_stb_i = '1') then
        ack_reg <= '1';

        if (wb_we_i = '1') then
          leds <= wb_dat_i(15 downto 0);
        end if;
      end if;
    end if;

  end process;

  wb_ack_o <= ack_reg;
  wb_dat_o <= (31 downto 16 => '0') & leds;

end architecture rtl;
