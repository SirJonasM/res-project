library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity irq_peripheral is
  generic (
    num_irqs : positive := 3 -- Set how many interrupts you want
  );
  port (
    clk   : in    std_logic;
    reset : in    std_logic; -- Assumed active-high based on your LED template

    -- Wishbone Bus Interface
    wb_adr_i : in    std_logic_vector(31 downto 0);
    wb_dat_i : in    std_logic_vector(31 downto 0);
    wb_dat_o : out   std_logic_vector(31 downto 0);
    wb_we_i  : in    std_logic;
    wb_sel_i : in    std_logic_vector(3 downto 0);
    wb_stb_i : in    std_logic;
    wb_cyc_i : in    std_logic;
    wb_ack_o : out   std_logic;

    -- Hardware Interrupt Inputs (single-cycle pulses)
    irq_pulses_i : in    std_logic_vector(num_irqs - 1 downto 0);
    -- Combined output to feed directly into NEORV32 mext_irq_i
    cpu_mext_o : out   std_logic
  );
end entity irq_peripheral;

architecture rtl of irq_peripheral is
  signal irq_status : std_logic_vector(num_irqs - 1 downto 0) := (others => '0');
  signal ack_reg    : std_logic                               := '0';
  
  -- ADD THIS: A dedicated register to safely hold data for the Wishbone bus
  signal rdata_reg  : std_logic_vector(31 downto 0)           := (others => '0');
begin

  cpu_mext_o <= '1' when (unsigned(irq_status) /= 0) else '0';

  process (clk) is
  begin
    if rising_edge(clk) then
      ack_reg <= '0'; 
      
      if (reset = '1') then
        irq_status <= (others => '0');
        rdata_reg  <= (others => '0');
      else
        if (wb_cyc_i = '1' and wb_stb_i = '1') then
          ack_reg <= '1';
          
          if (wb_we_i = '0') then
            -- 1. CAPTURE historical data into the read register right now
            rdata_reg <= (31 downto num_irqs => '0') & irq_status;
            
            -- 2. Simultaneously schedule the clear for the next clock edge
            irq_status <= irq_pulses_i;
          else
            irq_status <= irq_status or irq_pulses_i;
          end if;
        else
          irq_status <= irq_status or irq_pulses_i;
        end if;
      end if;
    end if;
  end process;

  wb_ack_o <= ack_reg;

  -- CHANGE THIS: Drive the bus using your safe read data register
  wb_dat_o <= rdata_reg;

end architecture rtl;
