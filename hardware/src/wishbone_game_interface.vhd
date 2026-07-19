library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity wishbone_mmio_interface is
  port (
    clk                : in    std_logic;
    system_reset       : in    std_logic;
    
    -- Physical Wishbone Ports
    wb_adr_i           : in    std_logic_vector(31 downto 0);
    wb_dat_i           : in    std_logic_vector(31 downto 0);
    wb_dat_o           : out   std_logic_vector(31 downto 0);
    wb_we_i            : in    std_logic;
    wb_sel_i           : in    std_logic_vector(3 downto 0);
    wb_stb_i           : in    std_logic;
    wb_cyc_i           : in    std_logic;
    wb_ack_o           : out   std_logic;

    -- Local Engine Tracking Interconnects
    player_x           : in    std_logic_vector(31 downto 0);
    player_y           : in    std_logic_vector(31 downto 0);
    score              : in    std_logic_vector(31 downto 0);
    speed_reg          : in    integer range 3 to 4;
    game_state_one_hot : in    std_logic_vector(3 downto 0);

    -- Local Hosted Outputs and Configuration Triggers
    bg_color_reg       : out   std_logic_vector(11 downto 0);
    wb_reset_req       : out   std_logic;
    wb_speed_write     : out   std_logic;
    wb_speed_val       : out   integer range 3 to 4
  );
end entity wishbone_mmio_interface;

architecture behavioral of wishbone_mmio_interface is
  signal bg_color_i : std_logic_vector(11 downto 0) := x"008";
begin
  bg_color_reg <= bg_color_i;

  -- Read Operations Matrix (Combinational Multiplexer Input Routing)
  process (all) is
  begin
    case wb_adr_i(5 downto 2) is
      when "0000" => wb_dat_o <= player_x;
      when "0001" => wb_dat_o <= player_y;
      when "0010" => wb_dat_o <= x"00000" & bg_color_i;
      when "0100" => wb_dat_o <= x"0000000" & game_state_one_hot;
      when "0101" => wb_dat_o <= score;
      when "0110" => wb_dat_o <= std_logic_vector(to_unsigned(speed_reg, 32));
      when others => wb_dat_o <= (others => '0');
    end case;
  end process;

  -- Synchronous Wishbone Target Protocol Interconnect writes
  process (clk, system_reset) is
  begin
    if system_reset = '1' then
      bg_color_i     <= x"008";
      wb_ack_o       <= '0';
      wb_reset_req   <= '0';
      wb_speed_write <= '0';
      wb_speed_val   <= 3;
    elsif rising_edge(clk) then
      wb_ack_o       <= '0';
      wb_reset_req   <= '0';
      wb_speed_write <= '0';

      if (wb_cyc_i = '1' and wb_stb_i = '1') then
        wb_ack_o <= '1';
        if wb_we_i = '1' then
          case wb_adr_i(5 downto 2) is
            when "0010" =>
              bg_color_i <= wb_dat_i(11 downto 0);
            when "0100" =>
              if wb_dat_i(0) = '1' then
                wb_reset_req <= '1';
              end if;
            when "0110" =>
              wb_speed_write <= '1';
              if to_integer(unsigned(wb_dat_i(3 downto 0))) < 3 then
                wb_speed_val <= 3;
              elsif to_integer(unsigned(wb_dat_i(3 downto 0))) > 4 then
                wb_speed_val <= 4;
              else
                wb_speed_val <= to_integer(unsigned(wb_dat_i(3 downto 0)));
              end if;
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture behavioral;
