{
  description = "A reproducible Rust, C/C++, and Python development environment with RISC-V Cross-Compilation Tools";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

		ent-cmd = pkgs.writeShellScriptBin "ent" ''
		  exec ${./bin/ent.sh} "$@"
		'';

        # 1. Parse the Rust toolchain straight from your project's configuration file
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./software/rust-toolchain.toml;

        vsg = pkgs.python3Packages.buildPythonPackage rec {
          pname = "vsg";
          version = "3.35.0";
          format = "pyproject";

          src = pkgs.fetchFromGitHub {
            owner = "jeremiah-c-leary";
            repo = "vhdl-style-guide";
            rev = "${version}"; # Matches tag v3.35.0
            hash = "sha256-ZFUCx7X7x0YopEAVG/eyxlHKkl82HM/N/r6tUFSLHAY="; 
          };
# Pass the version explicitly to the toolchain to bypass Git sandboxing
          SETUOT_GIT_VERSIONING_BYPASS = version;

          # Build-time dependencies
          nativeBuildInputs = with pkgs.python3Packages; [
            setuptools
            wheel
            setuptools-git-versioning
          ];

          # Runtime dependencies required by VSG
          propagatedBuildInputs = with pkgs.python3Packages; [
            pyyaml
          ];

          doCheck = false;
        };

        # 2. Isolated Python Environment (Now including your custom VSG package)
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
		  pyserial
          numpy
          pillow
          vsg # Added here so the binary is linked in your path
        ]);

        # 3. Native C/C++ Toolchain (For building host apps/utilities)
        nativeCToolchain = with pkgs; [
          gcc             # Native host compiler (gcc/g++)
          gnumake         # Standard Make utility
          cmake           # Build orchestration
          pkg-config      # System library locator
          gdb             # Native debugger
        ];

        # 4. RISC-V Bare-Metal Cross-Compiler Toolchain
        riscvToolchain = [
          pkgs.pkgsCross.riscv64-embedded.buildPackages.gcc
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            rustToolchain
            pkgs.cargo-binutils
            pythonEnv
            pkgs.typst
          ] 
          ++ nativeCToolchain 
          ++ riscvToolchain;

          buildInputs = with pkgs; [
			ent-cmd
			tio
            glib
            vulkan-loader
            # FIXED: Using the modern, flattened naming structure 
            libx11
            libxcursor
            libxrandr
            libxi
          ];

          shellHook = ''
			  ent help
          '';
        };
      });
}
