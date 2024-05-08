# CHIP8
Chip8 Emulator in Ruby

License: MIT

Dependencies:
* Gosu. Installation depends on your system. See: https://github.com/gosu/gosu/wiki

Usage:
1) Place ROMs in the ROMS/ folder
2) Execute: ruby emu.rb <ROM filename>
3) Keys are 0-9A-F on the keyboard (mapped to their CHIP-8 Hardware keys)

There's also an assembly viewer (dis.rb) which takes a ROM and pretty prints it (identifies instructions and arguments).

Unimplemented features:
1) No sound (could be easily added to the Gosu::Window class)
2) BNNN function because I haven't ran across anything yet that uses it.
3) 8XY6/8XYE instructions are implemented as VX = VX << or >> 1 instead of VX = VY << or >> 1

Thanks to:
  1) emudev.slack.com people
  2) Various websites, etc, that provided information about the CHIP-8 instruction set. Specific websites are called out in the code.
