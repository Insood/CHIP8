require 'gosu'

def h(n)
	n.to_s(16)
end

def load_rom(file)
	f = File.open(file,"rb")
	file_data = f.read()
	rom = []
	file_data.split("").each do |chr|
		rom << chr.ord()
	end
	#file_data.split("").each_slice(2) do |op_arr|
	#	rom << op_arr.join.unpack("n").first
	#end
	f.close()
	return rom
end

class Device < Gosu::Window
	def initialize(emulator)
		super emulator.DISPLAY_WIDTH*10, emulator.DISPLAY_HEIGHT*10
		self.caption = "CHIP-8 Emulator"
		@emulator    = emulator
		@emulator.set_device(self)
	end
	def update()
		@emulator.tick()
		#puts "TICK"
	end
	def draw()
		@emulator.DISPLAY_HEIGHT.times do |h|
			@emulator.DISPLAY_WIDTH.times do |w|
				color = (@emulator.display[h*@emulator.DISPLAY_WIDTH + w] == 1) ? Gosu::Color::WHITE : Gosu::Color::BLACK
				Gosu.draw_rect(w*10,h*10,10,10,color)
			end
		end
	end
	def key_status(key)
		return Gosu.button_down?( Gosu.char_to_button_id(key) )
	end
end

class Emulator
	attr_accessor :display, :DISPLAY_WIDTH, :DISPLAY_HEIGHT
	FONT = [
	0xF0,0x90,0x90,0x90,0xF0, # 0
	0x20,0x60,0x20,0x20,0x70, # 1
	0xF0,0x10,0xF0,0x80,0xF0, # 2
	0xF0,0x10,0xF0,0x10,0xF0, # 3
	0x90,0x90,0xF0,0x10,0x10, # 4
	0xF0,0x80,0xF0,0x10,0xF0, # 5
	0xF0,0x80,0xF0,0x90,0xF0, # 6
	0xF0,0x10,0x20,0x40,0x40, # 7
	0xF0,0x90,0xF0,0x90,0xF0, # 8
	0xF0,0x90,0xF0,0x10,0xF0, # 9
	0xF0,0x90,0xF0,0x90,0x90, # A
	0xE0,0x90,0xE0,0x90,0xE0, # B
	0xF0,0x80,0x80,0x80,0xF0, # C
	0xE0,0x90,0x90,0x90,0xE0, # D
	0xF0,0x80,0xF0,0x80,0xF0, # E
	0xF0,0x80,0xF0,0x80,0x80] # F
	def initialize(rom)
		@index          = 0
		@instruction    = 0x200
		@v              = [0] * 16
		@stack          = []
		@delay_timer    = 0
		@sound_timer    = 0
		@ram            = Emulator::FONT + [0]*(512-16*5) + rom # First 512 bytes are the font and some empty space
		@DISPLAY_WIDTH  = 64
		@DISPLAY_HEIGHT = 32
		@display        = [0] * (@DISPLAY_HEIGHT*@DISPLAY_WIDTH)
		@device         = nil
		@last_timer_update = Time.now()
		@error          = false
	end

	def set_device(device)
		@device = device
	end

	def pretty_print(arg)
		puts "0x#{h(@instruction)} : #{arg}"
	end

	def tick()
		# Called by Gosu at 60hz
		
		return if @error # We threw an exception during emulation, but don't close the window
		
		execute(16) # Run 16 commands.. because why not?
		update_timers()
	end
	
	def update_timers()
		@delay_timer -= 1 if @delay_timer > 0
		@sound_timer -= 1 if @sound_timer > 0
	end

	def execute(ops)
		# Will go ahead and execute up to 'ops' operations...
		ops.times do |x|
			op = (@ram[@instruction] << 8) | @ram[@instruction+1]
			begin
				handle_op(op)
			rescue NotImplementedError
				pretty_print "Ending Emulation - Op Code #{h(op)} Not Implemented"
				@error = true
				return
			end
			@instruction += 2
		end
	end
	
	def handle_op(op)
		if op == 0x00E0 then          # 00E0 - clear screen
			cls() 
		elsif op == 0x00EE then       # 00EE - return
			ret()
		elsif (op >> 12) == 0x1 then  # 1NNN - jump to
			jmp(op & 0xFFF)
		elsif (op >> 12) == 0x2 then  # 2NNN - call
			call(op & 0xFFF)
		elsif (op >> 12) == 0x3 then  # 3XNN - skip if VX == NN
			skip_next_if_vx_equal( (op >> 8) & 0XF ,op & 0xFF)
		elsif (op >> 12) == 0x4 then  # 4XNN - skip if VX != NN
			skip_next_if_vx_not_equal( (op >> 8) & 0XF, op & 0XFF)		
		elsif (op >> 12) == 0X6 then  # 6XNN - set VX = NN
			set_vx( (op >> 8) & 0XF, op & 0XFF)
		elsif (op >> 12) == 0X7 then  # 7XNN - set VX += NN
			add_vx( (op >> 8) & 0XF, op & 0XFF)
		elsif (op >> 12) == 0xA then  # ANNN - set I to
			set_i(op & 0xFFF)
		elsif (op >> 12) == 0xB then  # BNNN - jmp to + v0
			jmp_v0(op & 0xFFF)
		elsif (op >> 12) == 0xC then  # CXNN - jvx = rand & NN
			set_vx_rand( (op >> 8) & 0XF, op & 0XFF )
			
		## Ops involving two registers
		elsif (op >> 12) == 0X5 then  # 5XY0 - skip if vx == vy
			skip_next_if_vx_equal_vy( (op >> 8) & 0XF, (op >> 4) & 0XF)
		elsif (op >> 12) == 0X9 then  # 9XY0 - skip if vx != vy
			skip_next_if_vx_not_equal_vy( (op >> 8) & 0XF, (op >> 4) & 0XF)
		
		elsif (op >> 12) == 0X8 then  # A whole bunch of ops start with 0x8NNN
			cmd = op & 0XF            # And it's all based on the last 4-bits
			a   = (op >> 8 ) & 0XF
			b   = (op >> 4 ) & 0XF
			if cmd == 0X0 then        # 8XYO - VX = VY
				set_vx_to_vy(a,b)
			elsif cmd == 0x1 then     # 8XY1 - VX = VX | VY
				set_vx_to_vx_or_vy(a,b)
			elsif cmd == 0x2 then     # 8XY2: VX = VX & VY
				set_vx_to_vx_and_vy(a,b)
			elsif cmd == 0x3 then     # 8XY3: VX = VX xor VY
				set_vx_to_vx_xor_vy(a,b)
			elsif cmd == 0x4 then     # 8XY4: VX += VY (VF set to 1 on carry)
				add_vy_to_vx(a,b)
			elsif cmd == 0x5 then     # 8XY5: VX = VX - VY (VF set to 0 on borrow)
				subt_vy_from_vx(a,b)
			elsif cmd == 0x7 then     # 8XY7: VX = VY - VX (VF set to 0 on borrow)
				sub_vx_from_vy(a,b)
			elsif cmd == 0x6 then     # 8X06: VX = VX >> 1 (VF set to bit shifted out) 
				right_shift_vx(a)
			elsif cmd == 0xE then     # 8X0E: VX = VX << 1 (VF set to bit shifted out) 
				left_shift_vx(a)
			else
				raise NotImplementedError, "Unhandled 0x8 op code"
			end
		elsif (op >> 12) == 0XE then  # Hardware operations
			if (op & 0xFF) == 0X9E  then # EX9E: Skip next instruction if key stored in VX is pressed
				skip_if_pressed((op >> 8) & 0XF)
			elsif (op & 0xFF) == 0XA1 then # EXA1: Skip next instruction if key stored in VX is not pressed
				skip_if_not_pressed((op >> 8) & 0XF)
			else
				raise NotImplementedError, "Unhandled 0xE op code"
			end
		elsif (op >> 12) == 0XF then # Lots of various commands in "F"
			cmd = op & 0XFF # Stored in the last 8-bits
			arg = (op >> 8) & 0xF
			if cmd == 0X0A then    # FX0A: Wait for key press, store in VX
				wait_for_keypress(arg)
			elsif cmd == 0X07 then # FX07: VX = Delay Timer value
				set_vx_to_delay_timer(arg)
			elsif cmd == 0x15 then # FX15: Delay Timer = VX
				set_delay_timer_to_vx(arg)
			elsif cmd == 0x18 then # FX18: Sound Timer = VX
				set_sound_timer_to_vx(arg)
			elsif cmd == 0x1E then # FX1E: I += VX
				increment_index_register(arg)
			elsif cmd == 0x29 then # FX29: Sets I to location of character sprite for VX
				set_index_register_to_sprite(arg)
			elsif cmd == 0x33 then # FX33: Sets *I - *I+2 to BCD value of VX
				set_bcd_of_vx(arg)
			elsif cmd == 0x55 then # FX55: Stores V0-VX in memory at address I. I += N + 1
				copy_vx_to_memory(arg)
			elsif cmd == 0x65 then #FX65: Fills V0-VX with memory from address I. I += N + 1
				copy_memory_to_vx(arg)
			else
				raise NotImplementedError, "Unrecognized 0XF op-code (#{h(op)})"
			end
		elsif (op >> 12) == 0XD # DXYN - Draw sprite at vx, vy, height n, sprite at I
			draw( (op >> 8) & 0xF, (op >> 4) & 0XF, op & 0XF )
		else
			raise NotImplementedError, "Unrecognized op-code (#{h(op)})"
		end
	end

	def cls()
		pretty_print "CLS"
		raise NotImplementedError, "CLS"
	end

	def ret()
		pretty_print "RET"
		raise RuntimeError, "Stack Underflow" if @stack.length == 0
		@instruction = @stack.pop
		#raise NotImplementedError, "RET"
	end

	def jmp(address)
		pretty_print "JMP #{h(address)}"
		@instruction = address
		
		## TODO: FIX THIS?
		## @instruction is going to be incremented when jmp() finishes execution
		## Except - it shouldn't, we need to first execute whatever is at @instructon first
		## So need to back up one instruction
		@instruction -= 2
		#raise NotImplementedError, "JMP"
	end

	def call(address)
		pretty_print "CALL #{h(address)}"
		#raise NotImplementedError("CALL")
		@stack << @instruction   # Put the current address on top of the stack
		raise RuntimeError, "Stack Over Flow (Max Depth = 16)" if @stack.length > 16
		@instruction = address   # Set the next address of execution
	end

	def set_i(address)
		pretty_print "I = #{h(address)}"
		@index = address
	end

	def jmp_v0(address)
		pretty_print "JMP #{h(address)} + V0"
		raise NotImplementedError, "JMP+V0"
	end

	def skip_next_if_vx_equal(vx, val)
		pretty_print "SKP IF V#{h(vx)} (#{@v[vx]}) == #{h(val)}"
		@instruction+=2 if @v[vx] == val
		#raise NotImplementedError, "SKIP IF VX==NN"
	end

	def skip_next_if_vx_not_equal(vx, val)
		pretty_print "SKP IF V#{h(vx)} != #{h(val)}"
		@instruction += 2 if @v[vx] != val
		#raise NotImplementedError, "SKIP IF VX!=NN"
	end

	def skip_next_if_vx_equal_vy(vx,vy)
		pretty_print "SKP IF V#{h(vx)} == V#{h(vy)}"
		raise NotImplementedError, "SKIP IF VX==VY"
	end

	def skip_next_if_vx_not_equal_vy(vx, vy)
		pretty_print "SKP IF V#{h(vx)} != V#{h(vy)}"
		raise NotImplementedError, "SKIP IF VX!=VY"
	end

	def set_vx(vx, val)
		pretty_print "SET V#{h(vx)} = #{h(val)}"
		@v[vx] = val
	end

	def add_vx(vx, val)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} + #{h(val)}"
		#raise NotImplementedError, "VX+=NN"
		@v[vx] += val
	end

	def set_vx_rand(vx, val)
		pretty_print "SET V#{h(vx)} = RAND() & #{h(val)}"
		@v[vx] = (rand(255) & val) % 255
		#raise NotImplementedError, "VX=RAND()"
	end

	def set_vx_to_vy(vx,vy)
		pretty_print "SET V#{h(vx)} = V#{h(vy)}"
		
		@v[vx] = @v[vy]
		#raise NotImplementedError, "VX=VY"
	end

	def set_vx_to_vx_or_vy(vx,vy)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} | V#{h(vy)}"
		raise NotImplementedError, "VX|=VY"
	end

	def set_vx_to_vx_and_vy(vx,vy)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} & V#{h(vy)}"
		
		@v[vx] &= @v[vy]
		
		#raise NotImplementedError, "VX&=VY"
	end

	def set_vx_to_vx_xor_vy(vx,vy)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} ^ V#{h(vy)}"
		raise NotImplementedError, "VX^=VY"
	end

	def add_vy_to_vx(vx,vy)
		# 8XY4: VX += VY (VF set to 1 on carry)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} + V#{h(vy)}"
		
		result = @v[vx] + @v[vy]
		
		@v[0xF] = 1 if result > 255 # Overflow
		@v[vx] = result % 255
		
		#raise NotImplementedError, "VX+=VY"
	end

	def subt_vy_from_vx(vx,vy)
		# 8XY5: VX = VX - VY (VF set to 0 on borrow, 1 when not)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} - V#{h(vy)}"
		
		if @v[vx] > @v[vy] then
			@v[0xF] = 1 # No borrow
			@v[vx] -= @v[vy]
		else
			@v[vx]  = 0 # Underflow?
			@v[0xF] = 0 # Borrow
		end

		#raise NotImplementedError, "VX-=VY"
	end

	def sub_vx_from_vy(vx,vy)
		# 8XY7: VX = VY - VX (VF set to 0 on borrow)
		pretty_print "SET V#{h(vx)} = V#{h(vy)} - V#{h(vx)}"
		raise NotImplementedError, "VX=VY-VX"
	end

	def right_shift_vx(vx)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} >> 1"
		raise NotImplementedError, "VX>>1"
	end

	def left_shift_vx(vx)
		pretty_print "SET V#{h(vx)} = V#{h(vx)} << 1"
		raise NotImplementedError, "VX<<1"
	end

	def skip_if_pressed(vx)
		pretty_print "SKP IF KEY IN #{h(vx)} IS DOWN"
		
		@instruction += 2 if @device.key_status( @v[vx] )		
		#raise NotImplementedError, "KEY DOWN"
	end

	def skip_if_not_pressed(vx)
		pretty_print "SKP IF KEY IN #{h(vx)} IS NOT DOWN"
		@instruction +=2 if !@device.key_status( @v[vx] )
		#raise NotImplementedError, "KEY NOT DOWN"
	end

	def draw(vx, vy, n)
		# Blit an 8 pixel wide by N pixels high sprite
		# onto the screen starting at (vx,vy) [upper left corner]
		# See http://craigthomas.ca/blog/2015/02/19/writing-a-chip-8-emulator-draw-command-part-3/
		# For more explanation
		pretty_print "DRAW AT (#{h(vx)}, #{h(vy)}) Length: #{h(n)}"
		#raise NotImplementedError("DRAW")
		
		y = @v[vy]
		n.times do |n|
			x = @v[vx]                           # Recalculate X (left) at the start of each loop
			byte = @ram[@index + n]              # This is one byte of the sprite
			bit = 7                           
			while bit >= 0 do
				new_state = (byte >> bit) & 0x1  
				#puts new_state
				result = @display[ y*@DISPLAY_WIDTH + x] ^= new_state
				#puts result
				#puts @v[0xF]
				
				@v[0xF] |= (new_state^1) & result # Set VF=1 if the sprite was blank (new_state=0)
												  # but the previous pixel was turned on
												  # This will keep the pixel on, but just set the flag
												  # I think..
				
				x = (x+1) % @DISPLAY_WIDTH
				bit -= 1
			end
			y = (y+1) % @DISPLAY_HEIGHT # Overflow to the top
		end
		
	end

	def wait_for_keypress(vx)
		#FX0A: Wait for key press, store in VX
		pretty_print "WAIT -> #{h(vx)}"
		raise NotImplementedError, "WAIT FOR KEY"
	end

	def set_vx_to_delay_timer(vx)
		#FX07: VX = Delay Timer value
		pretty_print "SET V#{h(vx)} to DELAY TIMER"
		@v[vx] = @delay_timer
		#raise NotImplementedError, "SET VX=DELAY"
	end

	def set_delay_timer_to_vx(vx)
		#FX15: Delay Timer = VX
		pretty_print "SET DELAY TIMER TO V#{h(vx)}"
		@delay_timer = @v[vx]
		#raise NotImplementedError, "SET DELAY=VX"
	end

	def set_sound_timer_to_vx(vx)
		#FX18: Sound Timer = VX
		pretty_print "SET SOUND TIMER TO V#{h(vx)}"
		raise NotImplementedError, "SET TIMER=VX"
	end

	def increment_index_register(vx)
		#FX1E: I += VX
		pretty_print "I += V#{h(vx)}"
		raise NotImplementedError, "I+=VX"
	end

	def set_index_register_to_sprite(vx)
		#FX29: Sets I to location of character sprite for VX
		# These are the built in fonts for characters 0-F
		pretty_print "I = SPRITE(V#{h(vx)})"
		@index = @v[vx]*5 # Each font sprite is five bytes "tall"
		#raise NotImplementedError, "I=SPRITE"
	end

	def set_bcd_of_vx(vx)
		#FX33: Sets *I - *I+2 to BCD value of VX
		pretty_print "I = BCD(V#{h(vx)})"
		value = @v[vx]
		@ram[@index]   = value / 100
		@ram[@index+1] = value % 100
		@ram[@index+2] = value % 10
		#raise NotImplementedError("I=BCD")
	end

	def copy_vx_to_memory(vx)
		#FX55: Stores V0-VX in memory at address I. I += N + 1
		pretty_print "COPY V0-V#{h(vx)} TO *I"
		raise NotImplementedError, "*I_N = *VX"
	end

	def copy_memory_to_vx(vx)
		# FX65: Fills V0-VX with memory from address I. I += N + 1
		pretty_print "COPY *I TO V0-V#{h(vx)}"
		vx.times do |n|
			@v[n] = @ram[@index + n] % 255
		end
		#raise NotImplementedError, "V_X = *I_N"
	end

end


def main()
	rom = load_rom("ROMS/PONG")
	emu = Emulator.new(rom)
	dev = Device.new(emu)
	dev.show()
end

main()