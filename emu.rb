# frozen_string_literal: true

require 'gosu'

def h(n)
  n.to_s(16)
end

def load_rom(file)
  f = File.open(file, 'rb')
  file_data = f.read
  rom = []
  file_data.split('').each do |chr|
    rom << chr.ord
  end
  f.close
  rom
end

class Device < Gosu::Window
  def initialize(emulator)
    super emulator.DISPLAY_WIDTH * 10, emulator.DISPLAY_HEIGHT * 10
    self.caption = 'CHIP-8 Emulator'
    @emulator    = emulator
    @emulator.set_device(self)
  end

  def update
    @emulator.tick
  end

  def draw
    @emulator.DISPLAY_HEIGHT.times do |h|
      @emulator.DISPLAY_WIDTH.times do |w|
        color = @emulator.display[h * @emulator.DISPLAY_WIDTH + w] == 1 ? Gosu::Color::WHITE : Gosu::Color::BLACK
        Gosu.draw_rect(w * 10, h * 10, 10, 10, color)
      end
    end
  end

  def key_status(key)
    key = key.to_s(16)
    Gosu.button_down?(Gosu.char_to_button_id(key))
  end

  def any_key_pressed?
    (0..15).any? do |key|
      return key if key_status(key)
    end
    false
  end
end

class Emulator
  attr_accessor :display, :DISPLAY_WIDTH, :DISPLAY_HEIGHT

  FONT = [
    0xF0, 0x90, 0x90, 0x90, 0xF0, # 0
    0x20, 0x60, 0x20, 0x20, 0x70, # 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
    0x90, 0x90, 0xF0, 0x10, 0x10, # 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
    0xF0, 0x10, 0x20, 0x40, 0x40, # 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, # A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
    0xF0, 0x80, 0x80, 0x80, 0xF0, # C
    0xE0, 0x90, 0x90, 0x90, 0xE0, # D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
    0xF0, 0x80, 0xF0, 0x80, 0x80
  ].freeze # F
  def initialize(rom)
    @index = 0
    @instruction    = 0x200
    @v              = [0] * 16
    @stack          = []
    @delay_timer    = 0
    @sound_timer    = 0
    @ram            = Emulator::FONT + [0] * (512 - 16 * 5) + rom # First 512 bytes are the font and some empty space
    @ram += [0] * (1024 * 4 - @ram.length) # Pad to the whole 4096 bytes
    @DISPLAY_WIDTH  = 64
    @DISPLAY_HEIGHT = 32
    @display        = [0] * (@DISPLAY_HEIGHT * @DISPLAY_WIDTH)
    @device         = nil
    @last_timer_update = Time.now
    @error = false
  end

  def set_device(device)
    @device = device
  end

  def pretty_print(arg)
    op = (@ram[@instruction] << 8) | @ram[@instruction + 1]
    puts "0x#{h(@instruction)} : #{h(op).rjust(4, '0')} : #{arg}"
  end

  def tick
    # Called by Gosu at 60hz

    return if @error # We threw an exception during emulation, but don't close the window

    execute(16) # Run 16 commands.. because why not?
    update_timers
  end

  def update_timers
    @delay_timer -= 1 if @delay_timer.positive?
    @sound_timer -= 1 if @sound_timer.positive?
  end

  def execute(ops)
    # Will go ahead and execute up to 'ops' operations...
    ops.times do |_x|
      op = (@ram[@instruction] << 8) | @ram[@instruction + 1]
      begin
        handle_op(op)
      rescue NotImplementedError
        pretty_print "Ending Emulation - Op Code #{h(op)} Not Implemented"
        @error = true
        return
      rescue StandardError
        dump_ram
        raise
      end
      @instruction += 2
    end
  end

  def dump_ram
    time_stamp = Time.now.getutc.to_i
    File.open("#{time_stamp}.dump", 'wb') do |f|
      f.write(@ram)
    end
  end

  def sanity_check
    # Check that all registers have valid values
    raise "Delay Timer #{@delay_timer} out of range (0-255)" if @delay_timer.negative? || @delay_timer > 255
    raise "Sound Timer #{@sound_timer} out of range (0-255)" if @sound_timer.negative? || @sound_timer > 255

    16.times do |n|
      raise "V#{h(@v[n])} out of range (0-255)" if (@v[n]).negative? || @v[n] > 255
    end
    @ram.each_with_index do |byte, index|
      if byte.negative? || byte > 255 || !byte || byte.class != Integer
        dump_ram
        raise "Memory (Value: #{byte}, Address: #{h(index)}) out of range (0-255)"
      end
    end
  end

  def handle_op(op)
    sanity_check
    if op == 0x00E0          # 00E0 - clear screen
      cls
    elsif op == 0x00EE       # 00EE - return
      ret
    elsif (op >> 12) == 0x1  # 1NNN - jump to
      jmp(op & 0xFFF)
    elsif (op >> 12) == 0x2  # 2NNN - call
      call(op & 0xFFF)
    elsif (op >> 12) == 0x3  # 3XNN - skip if VX == NN
      skip_next_if_vx_equal((op >> 8) & 0xF, op & 0xFF)
    elsif (op >> 12) == 0x4  # 4XNN - skip if VX != NN
      skip_next_if_vx_not_equal((op >> 8) & 0xF, op & 0xFF)
    elsif (op >> 12) == 0x6  # 6XNN - set VX = NN
      set_vx((op >> 8) & 0xF, op & 0xFF)
    elsif (op >> 12) == 0x7  # 7XNN - set VX += NN
      add_vx((op >> 8) & 0xF, op & 0xFF)
    elsif (op >> 12) == 0xA  # ANNN - set I to
      set_i(op & 0xFFF)
    elsif (op >> 12) == 0xB  # BNNN - jmp to + v0
      jmp_v0(op & 0xFFF)
    elsif (op >> 12) == 0xC  # CXNN - jvx = rand & NN
      set_vx_rand((op >> 8) & 0xF, op & 0xFF)

    ## Ops involving two registers
    elsif (op >> 12) == 0x5  # 5XY0 - skip if vx == vy
      skip_next_if_vx_equal_vy((op >> 8) & 0xF, (op >> 4) & 0xF)
    elsif (op >> 12) == 0x9  # 9XY0 - skip if vx != vy
      skip_next_if_vx_not_equal_vy((op >> 8) & 0xF, (op >> 4) & 0xF)

    elsif (op >> 12) == 0x8  # A whole bunch of ops start with 0x8NNN
      cmd = op & 0xF # And it's all based on the last 4-bits
      a   = (op >> 8) & 0xF
      b   = (op >> 4) & 0xF
      case cmd
      when 0x0 # 8XYO - VX = VY
        set_vx_to_vy(a, b)
      when 0x1     # 8XY1 - VX = VX | VY
        set_vx_to_vx_or_vy(a, b)
      when 0x2     # 8XY2: VX = VX & VY
        set_vx_to_vx_and_vy(a, b)
      when 0x3     # 8XY3: VX = VX xor VY
        set_vx_to_vx_xor_vy(a, b)
      when 0x4     # 8XY4: VX += VY (VF set to 1 on carry)
        add_vy_to_vx(a, b)
      when 0x5     # 8XY5: VX = VX - VY (VF set to 0 on borrow)
        subt_vy_from_vx(a, b)
      when 0x7     # 8XY7: VX = VY - VX (VF set to 0 on borrow)
        subt_vx_from_vy(a, b)
      when 0x6     # 8X06: VX = VX >> 1 (VF set to bit shifted out)
        right_shift_vx(a)
      when 0xE     # 8X0E: VX = VX << 1 (VF set to bit shifted out)
        left_shift_vx(a)
      else
        raise NotImplementedError, 'Unhandled 0x8 op code'
      end
    elsif (op >> 12) == 0XE # Hardware operations
      if (op & 0xFF) == 0x9E # EX9E: Skip next instruction if key stored in VX is pressed
        skip_if_pressed((op >> 8) & 0xF)
      elsif (op & 0xFF) == 0xA1 # EXA1: Skip next instruction if key stored in VX is not pressed
        skip_if_not_pressed((op >> 8) & 0xF)
      else
        raise NotImplementedError, 'Unhandled 0xE op code'
      end
    elsif (op >> 12) == 0xF # Lots of various commands in "F"
      cmd = op & 0xFF # Stored in the last 8-bits
      arg = (op >> 8) & 0xF
      case cmd
      when 0x0A # FX0A: Wait for key press, store in VX
        wait_for_keypress(arg)
      when 0x07 # FX07: VX = Delay Timer value
        set_vx_to_delay_timer(arg)
      when 0x15 # FX15: Delay Timer = VX
        set_delay_timer_to_vx(arg)
      when 0x18 # FX18: Sound Timer = VX
        set_sound_timer_to_vx(arg)
      when 0x1E # FX1E: I += VX
        increment_index_register(arg)
      when 0x29 # FX29: Sets I to location of character sprite for VX
        set_index_register_to_sprite(arg)
      when 0x33 # FX33: Sets *I - *I+2 to BCD value of VX
        set_bcd_of_vx(arg)
      when 0x55 # FX55: Stores V0-VX in memory at address I. I += N + 1
        copy_vx_to_memory(arg)
      when 0x65 # FX65: Fills V0-VX with memory from address I. I += N + 1
        copy_memory_to_vx(arg)
      else
        raise NotImplementedError, "Unrecognized 0XF op-code (#{h(op)})"
      end
    elsif (op >> 12) == 0xD # DXYN - Draw sprite at vx, vy, height n, sprite at I
      draw((op >> 8) & 0xF, (op >> 4) & 0xF, op & 0xF)
    else
      raise NotImplementedError, "Unrecognized op-code (#{h(op)})"
    end
  end

  def cls
    pretty_print 'CLS'
    @display = [0] * (@DISPLAY_HEIGHT * @DISPLAY_WIDTH)

    # TODO: Check to see if VF needs to be set to 1 if we're overwritting something.
    # Gut feeling is no
  end

  def ret
    pretty_print 'RET'
    raise 'Stack Underflow' if @stack.empty?

    @instruction = @stack.pop
  end

  def jmp(address)
    pretty_print "JMP #{h(address)}"
    @instruction = address

    ## TODO: FIX THIS?
    ## @instruction is going to be incremented when jmp() finishes execution
    ## Except - it shouldn't, we need to first execute whatever is at @instructon first
    ## So need to back up one instruction
    @instruction -= 2
  end

  def call(address)
    pretty_print "CALL #{h(address)}"
    @stack << @instruction   # Put the current address on top of the stack
    raise 'Stack Over Flow (Max Depth = 16)' if @stack.length > 16

    @instruction = address   # Set the next address of execution
    @instruction -= 2 # Go back 2 so that this next instruction get executed properly (see jmp)
  end

  def set_i(address)
    pretty_print "I = #{h(address)}"
    @index = address
  end

  def jmp_v0(address)
    pretty_print "JMP #{h(address)} + V0"
    raise NotImplementedError, 'JMP+V0'
  end

  def skip_next_if_vx_equal(vx, val)
    pretty_print "SKP IF V#{h(vx)} (#{h(@v[vx])}) == #{h(val)}"
    @instruction += 2 if @v[vx] == val
  end

  def skip_next_if_vx_not_equal(vx, val)
    pretty_print "SKP IF V#{h(vx)} != #{h(val)}"
    @instruction += 2 if @v[vx] != val
  end

  def skip_next_if_vx_equal_vy(vx, vy)
    pretty_print "SKP IF V#{h(vx)} == V#{h(vy)}"
    @instruction += 2 if @v[vx] == @v[vy]
  end

  def skip_next_if_vx_not_equal_vy(vx, vy)
    pretty_print "SKP IF V#{h(vx)} != V#{h(vy)}"

    @instruction += 2 if @v[vx] != @v[vy]
  end

  def set_vx(vx, val)
    pretty_print "SET V#{h(vx)} = #{h(val)}"
    @v[vx] = val
  end

  def add_vx(vx, val)
    old_vx = @v[vx]
    @v[vx] = (@v[vx] + val) % 256
    pretty_print "SET V#{h(vx)} = V#{h(vx)} (#{old_vx}) + #{h(val)} -> (#{@v[vx]})"
  end

  def set_vx_rand(vx, val)
    pretty_print "SET V#{h(vx)} = RAND() & #{h(val)}"
    @v[vx] = (rand(255) & val) % 256
  end

  def set_vx_to_vy(vx, vy)
    pretty_print "SET V#{h(vx)} = V#{h(vy)} (#{@v[vy]}) -> (#{@v[vy]})"
    @v[vx] = @v[vy]
  end

  def set_vx_to_vx_or_vy(vx, vy)
    pretty_print "SET V#{h(vx)} = V#{h(vx)} (#{@v[vx]}) | V#{h(vy)} (#{@v[vy]})"
    @v[vx] |= @v[vy]
  end

  def set_vx_to_vx_and_vy(vx, vy)
    pretty_print "SET V#{h(vx)} = V#{h(vx)}  (#{@v[vx]}) & V#{h(vy)} (#{@v[vy]})"
    @v[vx] &= @v[vy]
  end

  def set_vx_to_vx_xor_vy(vx, vy)
    pretty_print "SET V#{h(vx)} = V#{h(vx)} ^ V#{h(vy)}"
    @v[vx] ^= @v[vy]
  end

  def add_vy_to_vx(vx, vy)
    # 8XY4: VX += VY (VF set to 1 on carry)
    pretty_print "SET V#{h(vx)} = V#{h(vx)} + V#{h(vy)}"

    result = @v[vx] + @v[vy]

    @v[0xF] = 1 if result > 255 # Overflow
    @v[vx] = result % 256
  end

  def subt_vy_from_vx(vx, vy)
    # 8XY5: VX = VX - VY (VF set to 0 on borrow, 1 when not)
    pretty_print "SET V#{h(vx)} = V#{h(vx)} - V#{h(vy)}"

    if @v[vx] > @v[vy]
      @v[0xF] = 1 # No borrow
      @v[vx] -= @v[vy]
    else
      @v[vx]  = (@v[vx] - @v[vy]) % 256
      @v[0xF] = 0 # Borrow
    end
  end

  def subt_vx_from_vy(vx, vy)
    # 8XY7: VX = VY - VX (VF set to 0 on borrow)
    pretty_print "SET V#{h(vx)} = V#{h(vy)} - V#{h(vx)}"

    if @v[vx] < @v[vy]
      @v[0xF] = 1 # No borrow
      @v[vx]  = @v[vy] - @v[vx]
    else
      @v[vx]  = (@v[vy] - @v[vx]) % 256
      @v[0xF] = 0 # Borrow
    end
  end

  def right_shift_vx(vx)
    # 8X06 : VX = VX >> 1
    # Set VX equal to VX bitshifted right 1.
    # VF is set to the least significant bit of VX prior to the shift.
    # Originally this opcode meant set VX equal to VY bitshifted right 1
    # but emulators and software seem to ignore VY now.
    # Note: This instruction was originally undocumented but functional
    # due to how the 8XXX instructions were implemented on teh COSMAC VIP.
    # (from https://github.com/trapexit/chip-8_documentation)
    #
    # Essentially any CHIP-8 game written before the superchip depends on
    # Vx = Vy << 1 and any CHIP-8 game written after the superchip
    # (including SCHIP-8 games) depend on `Vx = Vx << 1`
    pretty_print "SET V#{h(vx)} = V#{h(vx)} >> 1"

    @v[0xF] = @v[vx] & 1 # LSB
    @v[vx]  = @v[vx] >> 1
  end

  def left_shift_vx(vx)
    # 8XOE : VX = VX << 1
    # VF = MSB of VB (prior to the shift)
    pretty_print "SET V#{h(vx)} = V#{h(vx)} << 1"

    @v[0xF] = (@v[vx] >> 7) & 1 # MSB
    @v[vx]  = (@v[vx] << 1) % 256
  end

  def skip_if_pressed(vx)
    pretty_print "SKP IF KEY IN #{h(vx)} IS DOWN"

    @instruction += 2 if @device.key_status(@v[vx])
  end

  def skip_if_not_pressed(vx)
    pretty_print "SKP IF KEY IN #{h(vx)} IS NOT DOWN"
    @instruction += 2 unless @device.key_status(@v[vx])
  end

  def draw(vx, vy, n)
    # Blit an 8 pixel wide by N pixels high sprite
    # onto the screen starting at (vx,vy) [upper left corner]
    # See http://craigthomas.ca/blog/2015/02/19/writing-a-chip-8-emulator-draw-command-part-3/
    # For more explanation
    pretty_print "DRAW AT V#{h(vx)}, V#{h(vy)} (#{@v[vx]},#{@v[vy]}) Length: #{h(n)}"
    @v[0xF] = 0 # Clear the collision flag (no collision just yet, right?)

    y = @v[vy] % @DISPLAY_HEIGHT
    n.times do |n|
      x = @v[vx] % @DISPLAY_WIDTH # Recalculate X (left) at the start of each loop
      byte = @ram[@index + n] # This is one byte of the sprite
      bit = 7
      while bit >= 0
        new_state = (byte >> bit) & 0x1
        old_state = @display[y * @DISPLAY_WIDTH + x]
        @display[y * @DISPLAY_WIDTH + x] ^= new_state
        @v[0xF] |= (new_state & old_state) # Collision detection works by checking to
        # see if both the old and the new states
        # are on - if they're both on, the pixel is blank
        # and we set the collision flag

        x = (x + 1) % @DISPLAY_WIDTH
        bit -= 1
      end
      y = (y + 1) % @DISPLAY_HEIGHT # Overflow to the top
    end
  end

  def wait_for_keypress(vx)
    # FX0A: Wait for key press, store in VX
    pretty_print "WAIT -> #{h(vx)}"
    key_pressed = @device.any_key_pressed?
    if key_pressed
      @v[vx] = key_pressed
    else
      # TODO: : Fix this somehow - maybe put a flag in the tick() loop which
      # will halt any execution until a key is presesd. But this should work
      # for now.
      @instruction -= 2
    end
  end

  def set_vx_to_delay_timer(vx)
    # FX07: VX = Delay Timer value
    pretty_print "SET V#{h(vx)} to DELAY TIMER"
    @v[vx] = @delay_timer
  end

  def set_delay_timer_to_vx(vx)
    # FX15: Delay Timer = VX
    pretty_print "SET DELAY TIMER TO V#{h(vx)}"
    @delay_timer = @v[vx]
  end

  def set_sound_timer_to_vx(vx)
    # FX18: Sound Timer = VX
    pretty_print "SET SOUND TIMER TO V#{h(vx)}"
    @sound_timer = @v[vx]
  end

  def increment_index_register(vx)
    # FX1E: I += VX
    original_index = @index
    @index += @v[vx]
    pretty_print "I = I(#{h(original_index)}) + V#{h(vx)} (#{@v[vx]}) -> #{h(@index)}"
  end

  def set_index_register_to_sprite(vx)
    # FX29: Sets I to location of character sprite for VX
    # These are the built in fonts for characters 0-F
    pretty_print "I = SPRITE(V#{h(vx)})"
    @index = @v[vx] * 5 # Each font sprite is five bytes "tall"
  end

  def set_bcd_of_vx(vx)
    # FX33: Sets *I - *I+2 to BCD value of VX
    pretty_print "I = BCD(V#{h(vx)})"
    value = @v[vx]
    @ram[@index] = value / 100
    @ram[@index + 1] = (value % 100) / 10
    @ram[@index + 2] = value % 10
  end

  def copy_vx_to_memory(vx)
    # FX55: Stores V0-VX in memory at address I. I += N + 1
    pretty_print "COPY V0-V#{h(vx)} TO *I"

    (vx + 1).times do |n| # Because V0 is a valid argument
      @ram[@index + n] = @v[n]
    end
  end

  def copy_memory_to_vx(vx)
    # FX65: Fills V0-VX with memory from address I. I += N + 1
    pretty_print "COPY *I TO V0-V#{h(vx)}"
    (vx + 1).times do |n| # Because V0 is a valid argument
      @v[n] = @ram[@index + n] % 256
    end
  end
end

def main
  rom_name = ARGV[0]
  if ARGV.empty?
    puts 'emu.rb <name of ROM>'
    return
  end
  rom = load_rom("ROMS/#{rom_name}")
  emu = Emulator.new(rom)
  dev = Device.new(emu)
  dev.show
end

main
