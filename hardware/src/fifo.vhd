library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity fifo is
  port (
    clk     : in    std_logic;
    reset   : in    std_logic;
    wr_en   : in    std_logic;
    wr_data : in    std_logic_vector(7 downto 0);
    rd_en   : in    std_logic;
    rd_data : out   std_logic_vector(7 downto 0);
    empty   : out   std_logic;
    full    : out   std_logic
  );
end entity fifo;

architecture behavioral of fifo is

  type memory_array is array (0 to 15) of std_logic_vector(7 downto 0);

  signal fifo_mem : memory_array          := (others => (others => '0'));
  signal head     : integer range 0 to 15 := 0;
  signal tail     : integer range 0 to 15 := 0;
  signal count    : integer range 0 to 16 := 0;

begin

  empty   <= '1' when (count = 0) else
             '0';
  full    <= '1' when (count = 16) else
             '0';
  rd_data <= fifo_mem(tail);

  process (clk) is
  begin

    if rising_edge(clk) then
      if (reset = '1') then
        head  <= 0;
        tail  <= 0;
        count <= 0;
      else
        if (wr_en = '1' and count < 16) then
          fifo_mem(head) <= wr_data;
          if (head = 15) then
            head <= 0;
          else
            head <= head + 1;
          end if;
        end if;
        if (rd_en = '1' and count > 0) then
          if (tail = 15) then
            tail <= 0;
          else
            tail <= tail + 1;
          end if;
        end if;
        if (wr_en = '1' and rd_en = '0' and count < 16) then
          count <= count + 1;
        elsif (rd_en = '1' and wr_en = '0' and count > 0) then
          count <= count - 1;
        end if;
      end if;
    end if;

  end process;

end architecture behavioral;
