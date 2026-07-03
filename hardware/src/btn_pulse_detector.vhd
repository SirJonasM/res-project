library ieee;
  use ieee.std_logic_1164.all;

entity button_pulse_detector is
  port (
    clk_i   : in    std_ulogic; -- System clock (e.g., 100MHz)
    rstn_i  : in    std_ulogic; -- Active-low asynchronous/synchronous reset
    btn_i   : in    std_ulogic; -- Asynchronous button input from physical pin
    pulse_o : out   std_ulogic  -- Single-cycle active-high output pulse
  );
end entity button_pulse_detector;

architecture rtl of button_pulse_detector is

  -- 2-stage synchronizer shift register to prevent metastability
  signal btn_sync_reg : std_ulogic_vector(1 downto 0) := (others => '0');

  -- Delay register to remember the previous state for edge detection
  signal btn_sync_old : std_ulogic := '0';

begin

  sync_and_edge_proc : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rstn_i = '0') then
        btn_sync_reg <= (others => '0');
        btn_sync_old <= '0';
        pulse_o      <= '0';
      else
        -- Pass asynchronous input through 2 flip-flops
        btn_sync_reg(0) <= btn_i;
        btn_sync_reg(1) <= btn_sync_reg(0);

        -- Store the last cycle's stable state
        btn_sync_old <= btn_sync_reg(1);

        -- Generate a 1-clock-cycle pulse on the rising edge
        if ((btn_sync_reg(1) = '1') and (btn_sync_old = '0')) then
          pulse_o <= '1';
        else
          pulse_o <= '0';
        end if;
      end if;
    end if;

  end process sync_and_edge_proc;

end architecture rtl;
