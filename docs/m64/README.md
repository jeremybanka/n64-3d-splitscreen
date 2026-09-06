# ModRetro M64 quick guide

The M64 is an FPGA-based N64-compatible console with original cartridge and
controller support. This project does not depend on M64-specific extensions: it
produces a normal region-free N64 ROM and uses SummerCart64 as the flash/development
cartridge.

Before testing:

1. Update the M64 to the latest firmware from its Settings/Update interface.
2. Update SummerCart64 firmware with the matching `sc64deployer` release.
3. Insert SummerCart64 with power off, connect HDMI/controller, then power on.
4. Use the USB deployment task or select the ROM from the SummerCart menu.

The game uses 320x240 progressive video, a standard controller, no cartridge
save, and no Expansion Pak. If cartridge detection or launch fails, test the
SummerCart on original N64 hardware where possible and consult both vendors'
current compatibility/firmware notes.

Official resources:

- M64 manual: <https://support.modretro.com/en_us/m64-manual-r1tovFQgMg>
- M64 support/downloads: <https://support.modretro.com/en_us/categories/m64-HyGOw5zCl>
- SummerCart64 quick start: <https://github.com/Polprzewodnikowy/SummerCart64/blob/main/docs/00_quick_startup_guide.md>
