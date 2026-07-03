library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.textio.all;

entity cpu_bram is
  generic (
    mem_size_bytes : positive := 16384; -- Size of the BRAM in bytes (e.g., 16KB)
    hex_file_name  : string   := "firmware.hex"
  );
  port (
    -- Global Control
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- NEORV32 XBUS / Wishbone Slave Interface
    wb_adr_i : in    std_logic_vector(31 downto 0);
    wb_dat_i : in    std_logic_vector(31 downto 0);
    wb_dat_o : out   std_logic_vector(31 downto 0);
    wb_we_i  : in    std_logic;
    wb_sel_i : in    std_logic_vector(3 downto 0);
    wb_stb_i : in    std_logic;
    wb_cyc_i : in    std_logic;
    wb_ack_o : out   std_logic
  );
end entity cpu_bram;

architecture rtl of cpu_bram is

  -- Calculate number of 32-bit words
  constant mem_words : positive := mem_size_bytes / 4;

  -- Define the 32-bit word memory array

  type mem_type is array (0 to mem_words - 1) of std_logic_vector(31 downto 0);

  -- Impure function to read the text file and initialize the memory array

  impure function init_ram_from_hex (
    file_name : string
  ) return mem_type is

    file     text_file   : text open read_mode is file_name;
    variable text_line   : line;
    variable hex_val     : std_logic_vector(31 downto 0);
    variable ram_content : mem_type := (others => (others => '0'));

  begin

    for i in 0 to MEM_WORDS - 1 loop

      if (not endfile(text_file)) then
        readline(text_file, text_line);
        hread(text_line, hex_val); -- Reads 8 hex characters into 32-bit vector
        ram_content(i) := hex_val;
      else
        exit;                      -- File is shorter than memory size, leave the rest as 0
      end if;

    end loop;

    return ram_content;

  end function init_ram_from_hex;

  -- Signal declaration and initialization
  signal ram : mem_type := init_ram_from_hex(hex_file_name);

  -- Internal signals for address decoding and cycle tracking
  signal word_addr : integer range 0 to mem_words - 1;
  signal ram_rdata : std_logic_vector(31 downto 0);
  signal bus_req   : std_logic;

begin

  -- A valid access happens when both CYC and STB are high
  bus_req <= wb_cyc_i and wb_stb_i;

  -- Word address extraction (NEORV32 uses byte addresses, so strip the bottom 2 bits)
  -- Also mask the address bounds safely to match the size of your RAM
  word_addr <= to_integer(unsigned(wb_adr_i(31 downto 2))) mod mem_words;

  -----------------------------------------------------------------------------
  -- Synchronous RAM Read & Write Processes (Infers Dedicated FPGA BRAM)
  -----------------------------------------------------------------------------
  process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (bus_req = '1') then
        -- Read Operation (Pipeline Register)
        ram_rdata <= ram(word_addr);

        -- Byte-write enabled Write Operation
        if (wb_we_i = '1') then
          if (wb_sel_i(0) = '1') then
            ram(word_addr)(7 downto 0) <= wb_dat_i(7 downto 0);
          end if;
          if (wb_sel_i(1) = '1') then
            ram(word_addr)(15 downto 8) <= wb_dat_i(15 downto 8);
          end if;
          if (wb_sel_i(2) = '1') then
            ram(word_addr)(23 downto 16) <= wb_dat_i(23 downto 16);
          end if;
          if (wb_sel_i(3) = '1') then
            ram(word_addr)(31 downto 24) <= wb_dat_i(31 downto 24);
          end if;
        end if;
      end if;
    end if;

  end process;

  -- Continuous drive of read data port
  wb_dat_o <= ram_rdata;

  -----------------------------------------------------------------------------
  -- Wishbone Acknowledge Logic (1-Cycle Latency)
  -----------------------------------------------------------------------------
  process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        wb_ack_o <= '0';
      else
        -- ACK must be asserted exactly 1 clock cycle after the request is captured,
        -- provided the master is still asserting the strobe.
        wb_ack_o <= bus_req and (not wb_ack_o);
      end if;
    end if;

  end process;

end architecture rtl;
