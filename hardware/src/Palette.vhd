library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity palette is
  port (
    clk   : in    std_logic;
    index : in    integer range 0 to 63;
    red   : out   std_logic_vector(3 downto 0);
    green : out   std_logic_vector(3 downto 0);
    blue  : out   std_logic_vector(3 downto 0)
  );
end entity palette;

architecture behavioral of palette is

  type rom_type is array (0 to 63) of std_logic_vector(11 downto 0);

  constant color_table : rom_type :=
  (
    0      => x"000",
    1      => x"00B",
    2      => x"0B0",
    3      => x"0BB",
    4      => x"B00",
    5      => x"B0B",
    6      => x"BB0",
    7      => x"BBB",
    8      => x"005",
    9      => x"00F",
    10     => x"0B5",
    11     => x"0BF",
    12     => x"B05",
    13     => x"B0F",
    14     => x"BB5",
    15     => x"BBF",
    16     => x"050",
    17     => x"05B",
    18     => x"0F0",
    19     => x"0FB",
    20     => x"B50",
    21     => x"B5B",
    22     => x"BF0",
    23     => x"BFB",
    24     => x"055",
    25     => x"05F",
    26     => x"0F5",
    27     => x"0FF",
    28     => x"B55",
    29     => x"B5F",
    30     => x"BF5",
    31     => x"BFF",
    32     => x"500",
    33     => x"50B",
    34     => x"5B0",
    35     => x"5BB",
    36     => x"F00",
    37     => x"F0B",
    38     => x"FB0",
    39     => x"FBB",
    40     => x"505",
    41     => x"50F",
    42     => x"5B5",
    43     => x"5BF",
    44     => x"F05",
    45     => x"F0F",
    46     => x"FB5",
    47     => x"FBF",
    48     => x"550",
    49     => x"55B",
    50     => x"5F0",
    51     => x"5FB",
    52     => x"F50",
    53     => x"F5B",
    54     => x"FF0",
    55     => x"FFB",
    56     => x"555",
    57     => x"55F",
    58     => x"5F5",
    59     => x"5FF",
    60     => x"F55",
    61     => x"F5F",
    62     => x"FF5",
    63     => x"FFF",
    others => x"000"
  );

  signal color_data : std_logic_vector(11 downto 0);

begin

  process (clk) is
  begin

    if rising_edge(clk) then
      color_data <= COLOR_TABLE(index);
    end if;

  end process;

  red   <= color_data(11 downto 8);
  green <= color_data(7 downto 4);
  blue  <= color_data(3 downto 0);

end architecture behavioral;
