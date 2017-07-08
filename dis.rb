rom_name = ARGV[0]
if ARGV.length ==0 then
	puts "emu.rb <name of ROM>"
	exit
end
f = File.open("ROMS/#{rom_name}", "rb")

rom = f.read

$address    = 0x200
$current_op = 0x0

def h(n)
	n.to_s(16)
end

def pretty_print(arg)
	puts "0x#{h($address)} : #{h($current_op).rjust(4,"0")}:  #{arg}"
end

def cls()
	pretty_print "CLS"
end

def ret()
	pretty_print "RET"
end

def jmp(address)
	pretty_print "JMP #{h(address)}"
end

def call(address)
	pretty_print "CALL #{h(address)}"
end

def set_i(address)
	pretty_print "I = #{h(address)}"
end

def jmp_v0(address)
	pretty_print "JMP #{h(address)} + V0"
end

def skip_next_if_vx_equal(vx, val)
	pretty_print "SKP IF V#{h(vx)} == #{h(val)}"
end

def skip_next_if_vx_not_equal(vx, val)
	pretty_print "SKP IF V#{h(vx)} != #{h(val)}"
end

def skip_next_if_vx_equal_vy(vx,vy)
	pretty_print "SKP IF V#{h(vx)} == V#{h(vy)}"
end

def skip_next_if_vx_not_equal_vy(vx, vy)
	pretty_print "SKP IF V#{h(vx)} != V#{h(vy)}"
end

def set_vx(vx, val)
	pretty_print "SET V#{h(vx)} = #{h(val)}"
end

def add_vx(vx, val)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} + #{h(val)}"
end

def set_vx_rand(vx, val)
	pretty_print "SET V#{h(vx)} = RAND() & #{h(val)}"
end

def set_vx_to_vy(vx,vy)
	pretty_print "SET V#{h(vx)} = V#{h(vy)}"
end

def set_vx_to_vx_or_vy(vx,vy)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} | V#{h(vy)}"
end

def set_vx_to_vx_and_vy(vx,vy)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} & V#{h(vy)}"
end

def set_vx_to_vx_xor_vy(vx,vy)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} ^ V#{h(vy)}"
end

def add_vy_to_vx(vx,vy)
	# 8XY4: VX += VY (VF set to 1 on carry)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} + V#{h(vy)}"
end

def subt_vy_from_vx(vx,vy)
	# 8XY5: VX = VX - VY (VF set to 0 on borrow)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} - V#{h(vy)}"
end

def sub_vx_from_vy(vx,vy)
	# 8XY7: VX = VY - VX (VF set to 0 on borrow)
	pretty_print "SET V#{h(vx)} = V#{h(vy)} - V#{h(vx)}"
end

def right_shift_vx(vx)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} >> 1"
end

def left_shift_vx(vx)
	pretty_print "SET V#{h(vx)} = V#{h(vx)} << 1"
end

def skip_if_pressed(vx)
	pretty_print "SKP IF KEY IN #{h(vx)} IS DOWN"
end

def skip_if_not_pressed(vx)
	pretty_print "SKP IF KEY IN #{h(vx)} IS NOT DOWN"
end

def draw(vx, vy, n)
	pretty_print "DRAW AT (#{h(vx)}, #{h(vy)}) Height: #{h(n)}"
end

def wait_for_keypress(vx)
	#FX0A: Wait for key press, store in VX
	pretty_print "WAIT -> #{h(vx)}"
end

def set_vx_to_delay_timer(vx)
	#FX07: VX = Delay Timer value
	pretty_print "SET V#{h(vx)} to DELAY TIMER"
end

def set_delay_timer_to_vx(vx)
	#FX15: Delay Timer = VX
	pretty_print "SET DELAY TIMER TO V#{h(vx)}"
end

def set_sound_timer_to_vx(vx)
	#FX18: Sound Timer = VX
	pretty_print "SET SOUND TIMER TO V#{h(vx)}"
end

def increment_index_register(vx)
	#FX1E: I += VX
	pretty_print "I += V#{h(vx)}"
end

def set_index_register_to_sprite(vx)
	#FX29: Sets I to location of character sprite for VX
	pretty_print "I = SPRITE(V#{h(vx)})"
end

def set_bcd_of_vx(vx)
	#FX33: Sets *I - *I+2 to BCD value of VX
	pretty_print "I = BCD(V#{h(vx)})"
end

def copy_vx_to_memory(vx)
	#FX55: Stores V0-VX in memory at address I. I += N + 1
	pretty_print "COPY V0-V#{h(vx)} TO *I"
end

def copy_memory_to_vx(vx)
	# FX65: Fills V0-VX with memory from address I. I += N + 1
	pretty_print "COPY *I TO V0-V#{h(vx)}"
end



rom.split("").each_slice(2) do |op_arr|
	op = op_arr.join.unpack("n").first
	$current_op = op
	#pretty_print op.to_s(16)
	
	# Exact Match OP-codes
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
			pretty_print "Unhandled 0x8 op code?!"
		end
	elsif (op >> 12) == 0XE then  # Hardware operations
		if (op & 0xFF) == 0X9E  then # EX9E: Skip next instruction if key stored in VX is pressed
			skip_if_pressed((op >> 8) & 0XF)
		elsif (op & 0xFF) == 0XA1 then # EXA1: Skip next instruction if key stored in VX is not pressed
			skip_if_not_pressed((op >> 8) & 0XF)
		else
			pretty_print "Unhandled 0xE op code"
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
			pretty_print "Unrecognized 0XF op-code (#{h(op)})"
		end
	elsif (op >> 12) == 0XD # DXYN - Draw sprite at vx, vy, height n, sprite at I
		draw( (op >> 8) & 0xF, (op >> 4) & 0XF, op & 0XF )
	else
		pretty_print "Unrecognized op-code (#{h(op)})"
	end
	
	$address += 2
end


