library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library lib;
  use lib.image_data_pkg.all;

entity bram is
  port (
    clk    : in    std_logic;
    we_a   : in    std_logic;
    addr_a : in    std_logic_vector(16 downto 0);
    din_a  : in    std_logic_vector(17 downto 0);

    addr_b          : in    std_logic_vector(16 downto 0);
    pixel_sub_index : in    integer range 0 to 2;
    pixel_out       : out   std_logic_vector(5 downto 0)
  );
end entity bram;

architecture behavioral of bram is

  -- Image data which is generated with python from an image.
  signal my_bram_storage : rom_type := IMAGE_ROM;

  -- 16 bit word
  signal bram_data_out : std_logic_vector(17 downto 0);
  -- pixel offset in word
  signal sub_index_delayed : integer range 0 to 2;

begin

  process (clk) is
  begin

    if rising_edge(clk) then
      -- Write to BRAM
      if (we_a = '1') then
        my_bram_storage(to_integer(unsigned(addr_a))) <= din_a;
      end if;
      -- READ from BRAM
      bram_data_out <= my_bram_storage(to_integer(unsigned(addr_b)));

      sub_index_delayed <= pixel_sub_index;
    end if;

  end process;

  process (bram_data_out, sub_index_delayed) is
  begin

    -- get the pixel from the word.
    case sub_index_delayed is

      when 0 =>

        pixel_out <= bram_data_out(17 downto 12);

      when 1 =>

        pixel_out <= bram_data_out(11 downto 6);

      when 2 =>

        pixel_out <= bram_data_out(5 downto 0);

      when others =>

        pixel_out <= (others => '0');

    end case;

  end process;

end architecture behavioral;
