library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library lib;
  use lib.uart;

entity uart_wb is
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

    rsrx : in    std_logic;
    rstx : out   std_logic;

	uart_rx_irq_o: out std_logic
  );
end entity uart_wb;

architecture rtl of uart_wb is

  signal reg_addr : std_logic;
  signal reg_we   : std_logic;
  signal reg_re   : std_logic;

  signal reg_wdata : std_logic_vector(7 downto 0);
  signal reg_rdata : std_logic_vector(7 downto 0);

  signal ack_reg : std_logic;

begin

  uart_core : entity work.uart
    port map (
      clk   => clk,
      reset => reset,

      reg_addr => reg_addr,
      reg_we   => reg_we,
      reg_re   => reg_re,

      reg_wdata => reg_wdata,
      reg_rdata => reg_rdata,

      rsrx => rsrx,
      rstx => rstx,
	  uart_rx_irq_o => uart_rx_irq_o
    );

  process (clk) is
  begin

    if rising_edge(clk) then
      ack_reg <= '0';

      reg_we <= '0';
      reg_re <= '0';

      if (wb_cyc_i = '1' and wb_stb_i = '1') then
        ack_reg <= '1';

        reg_addr  <= wb_adr_i(2);
        reg_wdata <= wb_dat_i(7 downto 0);

        if (wb_we_i = '1') then
          reg_we <= '1';
        else
          reg_re <= '1';
        end if;
      end if;
    end if;

  end process;

  wb_ack_o <= ack_reg;

  wb_dat_o <= (31 downto 8 => '0') & reg_rdata;

end architecture rtl;
