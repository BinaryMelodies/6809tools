#! /usr/bin/python3

# Generates structures

import sys
from io import StringIO

data_file_name = None

def parse_data_file():
	global data_file_name
	global lex_instruction_list, yacc_instruction_list
	global m6800_instruction_dict, m6809_instruction_dict
	global m6800_instruction_matrix, m6809_instruction_matrix

	m6800_instructions = ""
	m6809_instructions = ""

	with open(data_file_name, 'r') as data:
		instructions = data.read()
		m6800_offset = instructions.find('@6800\n')
		m6809_offset = instructions.find('@6809\n')
		end_offset = instructions.find('@end\n')

		offsets = sorted({m6800_offset, m6809_offset, end_offset, len(instructions)})
		for i, offset in enumerate(offsets):
			if i == len(offsets):
				# last one is terminator
				break

			if offset == m6800_offset:
				#print("6800", offset)
				if offset == -1:
					# bare declarations
					offset = 0
				else:
					offset += len('@6800\n')
				m6800_instructions = instructions[offset:offsets[i + 1]]
			elif offset == m6809_offset:
				#print("6809", offset)
				offset += len('@6809\n')
				m6809_instructions = instructions[offset:offsets[i + 1]]
			else:
				continue # ignore separator

	m6800_instructionset = list(sorted(generate_instructions(m6800_instructions, m6809 = False), key = lambda triplet: triplet[0]))
	m6809_instructionset = list(sorted(generate_instructions(m6809_instructions, m6809 = True),  key = lambda triplet: triplet[0]))

	lex_instruction_list = {}
	for mnem, token, modes in m6800_instructionset:
		lex_instruction_list[(mnem, token)] = {'m6800'}
	for mnem, token, modes in m6809_instructionset:
		if (mnem, token) in lex_instruction_list:
			lex_instruction_list[(mnem, token)].add('m6809')
		else:
			lex_instruction_list[(mnem, token)] = {'m6809'}

	yacc_instruction_list = {triplet[0] for triplet in m6800_instructionset}
	yacc_instruction_list.update({triplet[0] for triplet in m6809_instructionset})

	yacc_instruction_list = list(sorted(yacc_instruction_list))

	m6800_instruction_dict = {instruction[0]: instruction[2] for instruction in m6800_instructionset}
	m6809_instruction_dict = {instruction[0]: instruction[2] for instruction in m6809_instructionset}

	m6800_instruction_matrix = generate_instruction_matrix(m6800_instructionset)
	m6809_instruction_matrix = generate_instruction_matrix(m6809_instructionset)

modelist = [''] + "ib iw d ix e rb rw r2 l".split(' ')

def generate_instructions(m6809_instructions, m6809 = True):
	m6809_instructionset = []
	for line in m6809_instructions.split('\n'):
		line = line.strip()
		if line == '':
			continue
		mnem, kind, base = line.split(' ')
		values = [int(value, 16) for value in base.split(',')]
		base = values[0]
		if kind == '0':
			# nilary
			token = 'MNEM0'
			modes = {'': base}
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1' or kind == '1*t':
			# unary
			token = 'MNEM1'
			modes = {'ib': base, 'd': base + 0x10, 'ix': base + 0x20, 'e': base + 0x30}
			if kind == '1*t':
				token = 'MNEM1T'
				del modes['ib']
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1w':
			# unary, word
			token = 'MNEM1'
			modes = {'iw': base, 'd': base + 0x10, 'ix': base + 0x20, 'e': base + 0x30}
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1i':
			# unary, only immediate
			token = 'MNEM1I'
			modes = {'ib': base}
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1x':
			# unary, only indexed
			token = 'MNEM1X'
			modes = {'ix': base}
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1t':
			# unary, no immediate
			token = 'MNEM1T'
			modes = {'d': base, 'ix': base + 0x60, 'e': base + 0x70}
			if not m6809:
				del modes['d']
			m6809_instructionset.append((mnem, token, modes))
		elif kind == '1r':
			# relative branch
			token = 'MNEM1R'
			if len(values) > 1:
				base2 = values[1]
			else:
				base2 = base + 0x1000
			modes = {'rb': base, 'rw': base2}
			if not m6809:
				del modes['rw']
			m6809_instructionset.append((mnem, token, modes))
			if m6809:
				modes = {'rw': base2}
				m6809_instructionset.append(('l' + mnem, token, modes))
		elif kind == '2':
			# binary
			token = 'MNEM2'
			modes = {'r2': base}
			m6809_instructionset.append((mnem, token, modes))
		elif kind == 'l':
			# register list
			token = 'MNEML'
			modes = {'l': base}
			m6809_instructionset.append((mnem, token, modes))
		else:
			print(kind)
			assert False
	return m6809_instructionset

def print_mnemonics_lex(lex_instruction_list, file):
	for (mnem, token), cpus in sorted(lex_instruction_list.items(), key = lambda mnem_token_cpus: (mnem_token_cpus[0][0], mnem_token_cpus[1])):
		if len(cpus) == 2:
			print(f"\"{mnem}\"\tyylval.i = MNEM_{mnem.upper()}; return {token};", file = file)
		else:
			print(f"<{','.join(sorted(cpus)).upper()}>\"{mnem}\"\tyylval.i = MNEM_{mnem.upper()}; return {token};", file = file)

def print_mnemonics_yacc(yacc_instruction_list, file):
	for mnem in yacc_instruction_list:
		print(f"\tMNEM_{mnem.upper()},", file = file)

def print_mnemonics_patterns(cpu, yacc_instruction_list, instruction_dict, file):
	print(f"static unsigned {cpu}_patterns[][_OPD_TYPE_COUNT] =\n{{", file = file)
	for mnem in yacc_instruction_list:
		modes = instruction_dict.get(mnem, set())
		print(f"\t[MNEM_{mnem.upper()}] = " + "{ " + ', '.join(hex(modes[mode]) if mode in modes else 'UNDEF' for mode in modelist) + " },", file = file)
	print("};", file = file)

def generate_instruction_matrix(m6809_instructionset):
	m6809_instruction_matrix = [None] * 256
	for mnem, token, modes in m6809_instructionset:
		for mode in reversed(modelist):
			matrix = m6809_instruction_matrix
			if mode not in modes:
				continue
			value = modes[mode]
			if value > 0xFF:
				prefix = value >> 8
				if matrix[prefix] is None:
					matrix[prefix] = [None] * 256
				assert type(matrix[prefix]) is list
				matrix = matrix[prefix]
				value &= 0xFF
			if matrix[value] is not None:
				# duplicate
				if not mnem.startswith('lb'):
					# LB* should override it
					continue
			matrix[value] = (mnem, mode)
	return m6809_instruction_matrix

def generate_table(matrix, indent = '\t', m6809 = True, file = None):
	assert file is not None
	print(f"{indent}switch((op = FETCH(cpu)))", file = file)
	print(f"{indent}{{", file = file)
	has_undefined = False
	for index, entry in enumerate(matrix):
		if entry is None:
			has_undefined = True
			continue
		print(f"{indent}case 0x{index:02X}:", file = file)
		if type(entry) is list:
			generate_table(entry, indent = indent + '\t', m6809 = m6809, file = file)
		else:
			(mnem, mode) = entry
			mode_text = {'': '', 'd': ' dir', 'rb': ' rel8', 'rw': ' rel16', 'ib': ' imm8', 'iw': ' imm16', 'r2': ' reg, reg', 'ix': ' idx', 'l': ' lst', 'e': ' ext'}[mode]
			print(f"{indent}\t/* {mnem.upper()}{mode_text} */", file = file)
			if mode == '':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\n\");", file = file)
				if mnem[-1] in {'a', 'b', 'd', 'u', 's', 'x', 'y'} or mnem[-2:] == 'cc':
					reg = mnem[-1] if mnem[-2:] != 'cc' else mnem[-2:]
					rd, wr = {
						'a': ('GETA(cpu)', 'SETA(cpu, $)'),
						'b': ('GETB(cpu)', 'SETB(cpu, $)'),
					}.get(reg, (f'cpu->{reg}', f'cpu->{reg} = $'))
			elif mode == 'ib':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\tvalue = FETCH(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"#$%X\\n\", value);", file = file)
				rd = "value"
				wr = None
			elif mode == 'iw':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\tvalue = FETCHW(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"#$%X\\n\", value);", file = file)
				rd = "value"
				wr = None
			elif mode == 'rb':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\tvalue = (int8_t)FETCH(cpu);", file = file)
				print(f"{indent}\tvalue += cpu->pc;", file = file)
				print(f"{indent}\tDEBUG(cpu, \"$%X\\n\", value);", file = file)
				rd = "value"
				wr = None
			elif mode == 'rw':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\tvalue = FETCHW(cpu);", file = file)
				print(f"{indent}\tvalue += cpu->pc;", file = file)
				print(f"{indent}\tDEBUG(cpu, \"$%X\\n\", value);", file = file)
				rd = "value"
				wr = None
			elif mode == 'd':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\taddress = DIRECT(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"<$%X\\n\", address & 0xFF);", file = file)
				rd = "m6809_read_byte(address)"
				wr = "m6809_write_byte(address, $)"
			elif mode == 'ix':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				if m6809:
					print(f"{indent}\taddress = m6809_index(cpu, FETCH(cpu));", file = file)
					print(f"{indent}\tDEBUG(cpu, \"\\n\");", file = file)
				else:
					print(f"{indent}\taddress = INDEXED(cpu);", file = file)
					print(f"{indent}\tDEBUG(cpu, \"$%X,x\\n\", address - cpu->x);", file = file)
				rd = "m6809_read_byte(address)"
				wr = "m6809_write_byte(address, $)"
			elif mode == 'e':
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\taddress = FETCHW(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"$%X\\n\", address);", file = file)
				rd = "m6809_read_byte(address)"
				wr = "m6809_write_byte(address, $)"
			elif mode == 'r2':
				print(f"{indent}\top = FETCH(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t%s,%s\\n\", m6809_regname[(op) >> 4], m6809_regname[op & 0xF]);", file = file)
			elif mode == 'l':
				print(f"{indent}\top = FETCH(cpu);", file = file)
				print(f"{indent}\tDEBUG(cpu, \"\\t{mnem}\\t\");", file = file)
				print(f"{indent}\tfor(int i = 0; i < 8; i++)", file = file)
				print(f"{indent}\t{{", file = file)
				print(f"{indent}\t\tif(((op >> i) & 1))", file = file)
				print(f"{indent}\t\t{{", file = file)
				print(f"{indent}\t\t\tif(i && ((op >> (i - 1)) & 1)) DEBUG(cpu, \",\");", file = file)
				print(f"{indent}\t\t\tDEBUG(cpu, \"%s\", m6809_stack{mnem[-1]}_regname[i]);", file = file)
				print(f"{indent}\t\t}}", file = file)
				print(f"{indent}\t}}", file = file)
				print(f"{indent}\tDEBUG(cpu, \"\\n\");", file = file)

			if mnem == 'aba':
				# 6800
				print(f"{indent}\tSETA(cpu, m6809_adc(cpu, GETA(cpu), GETB(cpu), 1));", file = file)
			elif mnem == 'abx':
				# 6809
				print(f"{indent}\tcpu->x += (uint8_t)GETB(cpu);", file = file)
			elif mnem in {'adca', 'adcb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tSET{r}(cpu, m6809_adc(cpu, GET{r}(cpu), {rd}, GETC(cpu)));", file = file)
			elif mnem in {'adda', 'addb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tSET{r}(cpu, m6809_adc(cpu, GET{r}(cpu), {rd}, 0));", file = file)
			elif mnem == 'addd':
				# 6809
				print(f"{indent}\tcpu->d = m6809_addw(cpu, cpu->d, {rd.replace('_byte', '_word')});", file = file)
			elif mnem in {'anda', 'andb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tvalue = GET{r}(cpu) & {rd};", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
				print(f"{indent}\tSET{r}(cpu, value);", file = file)
			elif mnem == 'andcc':
				# 6809
				print(f"{indent}\tcpu->cc &= value;", file = file)
			elif mnem in {'asl', 'asla', 'aslb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_asl(cpu, {rd})") + ";", file = file)
			elif mnem in {'asr', 'asra', 'asrb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_asr(cpu, {rd})") + ";", file = file)
			elif mnem in {'bra', 'lbra'}:
				print(f"{indent}\tcpu->pc = {rd};", file = file)
			elif mnem in {'brn', 'lbrn'}:
				# 6809
				pass
			elif mnem in {'bsr', 'lbsr'}:
				print(f"{indent}\tPUSH(s, cpu, cpu->pc);", file = file)
				print(f"{indent}\tPUSH(s, cpu, cpu->pc >> 8);", file = file)
				print(f"{indent}\tcpu->pc = {rd};", file = file)
			elif mnem in {'bita', 'bitb'}:
				print(f"{indent}\tm6809_test(cpu, GET{r}(cpu) & {rd});", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
			elif mnem.startswith('b') or mnem.startswith('lb'):
				# except bra/lbra, bsr/lbsr, brn/lbrn and bit[ab]
				print(f"{indent}\tif(m6809_check_condition(cpu, op))", file = file)
				print(f"{indent}\t{{", file = file)
				print(f"{indent}\t\tcpu->pc = {rd};", file = file)
				print(f"{indent}\t}}", file = file)
			elif mnem == 'cba':
				# 6800
				print(f"{indent}\tm6809_sbc(cpu, GETA(cpu), GETB(cpu), 0);", file = file)
			elif mnem in {'clc', 'cli', 'clv'}:
				# 6800
				print(f"{indent}\tcpu->cc &= ~CC_{mnem[-1].upper()};", file = file)
			elif mnem in {'clr', 'clra', 'clrb'}:
				print(f"{indent}\t" + wr.replace('$', "0") + ";", file = file)
				print(f"{indent}\tcpu->cc = (cpu->cc & ~(CC_C | CC_V | CC_N)) | CC_Z;", file = file)
			elif mnem in {'cmpa', 'cmpb', 'cmpd', 'cmps', 'cmpu', 'cmpx', 'cmpy', 'cpx'}:
				r = mnem[-1]
				if r in {'a', 'b'}:
					print(f"{indent}\tm6809_sbc(cpu, GET{r.upper()}(cpu), {rd}, 0);", file = file)
				else:
					print(f"{indent}\tm6809_subw(cpu, (cpu)->{r}, {rd.replace('_byte', '_word')});", file = file)
				# TODO: 6800 CPX overflow from least significant byte???
			elif mnem in {'com', 'coma', 'comb'}:
				print(f"{indent}\tvalue = ~({rd});", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc = (cpu->cc & ~CC_V) | CC_C;", file = file)
				print(f"{indent}\t" + wr.replace('$', "value") + ";", file = file)
			elif mnem == 'cwai':
				# 6809
				print(f"{indent}\tcpu->cc = (cpu->cc & value) | CC_E;", file = file)
				print(f"{indent}\tm6809_wait_interrupt(cpu);", file = file)
			elif mnem == 'daa':
				print(f"{indent}\tm6809_dec_adj(cpu);", file = file)
			elif mnem in {'dec', 'deca', 'decb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_inc_dec(cpu, {rd}, -1)") + ";", file = file)
			elif mnem in {'dex', 'des'}:
				# 6800
				print(f"{indent}\tcpu->{mnem[-1]} --;", file = file)
				if mnem == 'dex':
					print(f"{indent}\tif(cpu->x == 0)", file = file)
					print(f"{indent}\t\tcpu->cc |= CC_Z;", file = file)
					print(f"{indent}\telse", file = file)
					print(f"{indent}\t\tcpu->cc &= ~CC_Z;", file = file)
			elif mnem in {'eora', 'eorb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tvalue = GET{r}(cpu) ^ {rd};", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
				print(f"{indent}\tSET{r}(cpu, value);", file = file)
			elif mnem == 'exg':
				# 6809
				print(f"{indent}\tvalue = m6809_read_register(cpu, op >> 4);", file = file)
				print(f"{indent}\tm6809_write_register(cpu, op >> 4, m6809_read_register(cpu, op & 0xF));", file = file)
				print(f"{indent}\tm6809_write_register(cpu, op & 0xF, value);", file = file)
			elif mnem in {'inc', 'inca', 'incb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_inc_dec(cpu, {rd}, 1)") + ";", file = file)
			elif mnem in {'inx', 'ins'}:
				# 6800
				print(f"{indent}\tcpu->{mnem[-1]} ++;", file = file)
				if mnem == 'dex':
					print(f"{indent}\tif(cpu->x == 0)", file = file)
					print(f"{indent}\t\tcpu->cc |= CC_Z;", file = file)
					print(f"{indent}\telse", file = file)
					print(f"{indent}\t\tcpu->cc &= ~CC_Z;", file = file)
			elif mnem == 'jmp':
				print(f"{indent}\tcpu->pc = address;", file = file)
			elif mnem == 'jsr':
				print(f"{indent}\tPUSH(s, cpu, cpu->pc);", file = file)
				print(f"{indent}\tPUSH(s, cpu, cpu->pc >> 8);", file = file)
				print(f"{indent}\tcpu->pc = address;", file = file)
			elif mnem in {'lda', 'ldb', 'ldd', 'lds', 'ldu', 'ldx', 'ldy', 'ldaa', 'ldab'}:
				r = mnem[-1]
				if r in {'a', 'b'}:
					print(f"{indent}\tvalue = {rd};", file = file)
					print(f"{indent}\tm6809_test(cpu, value);", file = file)
					print(f"{indent}\tSET{r.upper()}(cpu, value);", file = file)
				else:
					print(f"{indent}\tvalue = {rd.replace('_byte', '_word')};", file = file)
					print(f"{indent}\tm6809_testw(cpu, value);", file = file)
					print(f"{indent}\tcpu->{r} = value;", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
			elif mnem in {'leas', 'leau', 'leax', 'leay'}:
				# 6809
				r = mnem[-1]
				print(f"{indent}\tcpu->{r} = address;", file = file)
				if r in {'x', 'y'}:
					print(f"{indent}\tif(cpu->{r} == 0)", file = file)
					print(f"{indent}\t\tcpu->cc |= CC_Z;", file = file)
					print(f"{indent}\telse", file = file)
					print(f"{indent}\t\tcpu->cc &= ~CC_Z;", file = file)
			elif mnem in {'lsr', 'lsra', 'lsrb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_lsr(cpu, {rd})") + ";", file = file)
			elif mnem == 'mul':
				# 6809
				print(f"{indent}\tcpu->d = (uint8_t)GETA(cpu) * (uint8_t)GETB(cpu);", file = file)
				print(f"{indent}\tif(cpu->d == 0)", file = file)
				print(f"{indent}\t\tcpu->cc |= CC_Z;", file = file)
				print(f"{indent}\telse", file = file)
				print(f"{indent}\t\tcpu->cc &= ~CC_Z;", file = file)
				print(f"{indent}\tif((cpu->d & 0x80))", file = file)
				print(f"{indent}\t\tcpu->cc |= CC_C;", file = file)
				print(f"{indent}\telse", file = file)
				print(f"{indent}\t\tcpu->cc &= ~CC_C;", file = file)
			elif mnem in {'neg', 'nega', 'negb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_neg(cpu, {rd})") + ";", file = file)
			elif mnem == 'nop':
				pass
			elif mnem in {'ora', 'orb', 'oraa', 'orab'}:
				r = mnem[-1].upper()
				print(f"{indent}\tvalue = GET{r}(cpu) | {rd};", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
				print(f"{indent}\tSET{r}(cpu, value);", file = file)
			elif mnem == 'orcc':
				# 6809
				print(f"{indent}\tcpu->cc |= value;", file = file)
			elif mnem in {'psha', 'pshb'}:
				# 6800
				r = mnem[-1]
				print(f"{indent}\tPUSH(s, cpu, GET{r.upper()}(cpu));", file = file)
			elif mnem in {'pshs', 'pshu'}:
				# 6809
				print(f"{indent}\tPUSHM({mnem[-1]}, cpu, op);", file = file)
			elif mnem in {'pula', 'pulb'}:
				# 6800
				r = mnem[-1]
				print(f"{indent}\tSET{r.upper()}(cpu, PULL(s, cpu));", file = file)
			elif mnem in {'puls', 'pulu'}:
				# 6809
				print(f"{indent}\tPULLM({mnem[-1]}, cpu, op);", file = file)
			elif mnem in {'rol', 'rola', 'rolb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_rol(cpu, {rd})") + ";", file = file)
			elif mnem in {'ror', 'rora', 'rorb'}:
				print(f"{indent}\t" + wr.replace('$', f"m6809_ror(cpu, {rd})") + ";", file = file)
			elif mnem == 'rti':
				print(f"{indent}\tm6809_return_interrupt(cpu);", file = file)
			elif mnem == 'rts':
				print(f"{indent}\tcpu->pc = PULL(s, cpu) << 8;", file = file)
				print(f"{indent}\tcpu->pc |= PULL(s, cpu);", file = file)
			elif mnem == 'sba':
				# 6800
				print(f"{indent}\tSETA(cpu, m6809_sbc(cpu, GETA(cpu), GETB(cpu), 0));", file = file)
			elif mnem in {'sbca', 'sbcb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tSET{r}(cpu, m6809_sbc(cpu, GET{r}(cpu), {rd}, GETC(cpu)));", file = file)
			elif mnem in {'sec', 'sei', 'sev'}:
				# 6800
				print(f"{indent}\tcpu->cc |= CC_{mnem[-1].upper()};", file = file)
			elif mnem == 'sex':
				# 6809
				print(f"{indent}\tif((GETB(cpu) & 0x80))", file = file)
				print(f"{indent}\t{{", file = file)
				print(f"{indent}\t\tcpu->d |= -0x100;", file = file)
				print(f"{indent}\t\tcpu->cc = (cpu->cc & ~CC_Z) | CC_N;", file = file)
				print(f"{indent}\t}}", file = file)
				print(f"{indent}\telse", file = file)
				print(f"{indent}\t{{", file = file)
				print(f"{indent}\t\tcpu->d &= 0xFF;", file = file)
				print(f"{indent}\t\tif(cpu->d == 0)", file = file)
				print(f"{indent}\t\t\tcpu->cc = (cpu->cc & CC_N) | CC_Z;", file = file)
				print(f"{indent}\t\telse", file = file)
				print(f"{indent}\t\t\tcpu->cc &= ~(CC_Z | CC_N);", file = file)
				print(f"{indent}\t}}", file = file)
			elif mnem in {'sta', 'stb', 'std', 'sts', 'stu', 'stx', 'sty', 'staa', 'stab'}:
				r = mnem[-1]
				if r in {'a', 'b'}:
					print(f"{indent}\tvalue = GET{r.upper()}(cpu);", file = file)
					print(f"{indent}\tm6809_test(cpu, value);", file = file)
					print(f"{indent}\t" + wr.replace('$', "value") + ";", file = file)
				else:
					print(f"{indent}\tvalue = cpu->{r};", file = file)
					print(f"{indent}\tm6809_testw(cpu, value);", file = file)
					print(f"{indent}\t" + wr.replace('_byte', '_word').replace('$', "value") + ";", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
			elif mnem in {'suba', 'subb'}:
				r = mnem[-1].upper()
				print(f"{indent}\tSET{r}(cpu, m6809_sbc(cpu, GET{r}(cpu), {rd}, 0));", file = file)
			elif mnem == 'subd':
				# 6809
				print(f"{indent}\tcpu->d = m6809_subw(cpu, cpu->d, {rd.replace('_byte', '_word')});", file = file)
			elif mnem in {'swi', 'swi2', 'swi3'}:
				print(f"{indent}\tm6809_do_interrupt(cpu, IV_{mnem.upper()});", file = file)
			elif mnem in {'sync'}:
				# 6809
				print(f"{indent}\tm6809_sync_interrupt(cpu);", file = file)
			elif mnem in {'tab', 'tba'}:
				# 6800
				s = mnem[1].upper()
				d = mnem[2].upper()
				print(f"{indent}\tvalue = GET{s}(cpu);", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tSET{d}(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
			elif mnem == 'tap':
				# 6800
				print(f"{indent}\tcpu->cc = GETA(cpu) & 0x3F;", file = file)
			elif mnem == 'tpa':
				# 6800
				print(f"{indent}\tSETA(cpu, cpu->cc);", file = file)
			elif mnem == 'tfr':
				# 6809
				print(f"{indent}\tvalue = m6809_read_register(cpu, op >> 4);", file = file)
				print(f"{indent}\tif(m6809_regsize(op >> 4) == 1)", file = file)
				print(f"{indent}\t\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\telse", file = file)
				print(f"{indent}\t\tm6809_testw(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc &= ~CC_V;", file = file)
				print(f"{indent}\tm6809_write_register(cpu, op & 0xF, value);", file = file)
			elif mnem in {'tsx', 'txs'}:
				# 6800
				s = mnem[1]
				d = mnem[2]
				print(f"{indent}\tm6809_test(cpu, cpu->{d} = cpu->{s});", file = file)
			elif mnem in {'tst', 'tsta', 'tstb'}:
				print(f"{indent}\tvalue = {rd};", file = file)
				print(f"{indent}\tm6809_test(cpu, value);", file = file)
				print(f"{indent}\tcpu->cc = (cpu->cc & ~CC_V) | CC_C;", file = file)
			elif mnem == 'wai':
				# 6800
				print(f"{indent}\tm6809_wait_interrupt(cpu);", file = file)
			else:
				print(mnem, file = sys.stderr)
				print(f"{indent}\t/* TODO */", file = file)
		print(f"{indent}\tbreak;", file = file)
	if has_undefined:
		print(f"{indent}default:", file = file)
		print(f"{indent}\tUNDEFINED();", file = file)
	print(f"{indent}}}", file = file)

#print("### C/EMU")

def print_emulation_table(cpu, instructionmatrix, m6809, file):
	print(f"""static void do_{cpu}_step(m6809_t * cpu)
{{
	uint16_t address;
	uint16_t value;
	uint8_t op;""", file = file)
	generate_table(instructionmatrix, m6809 = m6809, file = file)
	print("}", file = file)

def main():
	global data_file_name

	output_file = None
	i = 1
	while i < len(sys.argv):
		arg = sys.argv[i]
		if arg.startswith('-'):
			if arg.startswith('-o'):
				if len(arg) == 2:
					i += 1
					if i >= len(sys.argv):
						print("Error: expected filename after -o flag", file = sys.stderr)
						exit(1)
					fn = sys.argv[i]
				else:
					fn = arg[2:]
				if output_file is not None:
					print("Error: multiple output files specified, ignoring `{fn}'", file = sys.stderr)
				else:
					output_file = fn
			else:
				print(f"Error: unknown flag {arg}", file = sys.stderr)
				exit(1)
		else:
			if data_file_name is None:
				data_file_name = arg
			else:
				print(f"Error: unexpected argument {arg}", file = sys.stderr)
				exit(1)
		i += 1

	if data_file_name is None:
		data_file_name = "6809.dat"
	parse_data_file()

	with open(output_file, 'w') as outfile:
		print("@comment This file is automatically generated", file = outfile)

		print("@store INCLUDE_MNEMONICS_LEX", file = outfile)
		print_mnemonics_lex(lex_instruction_list, file = outfile)

		print("@store INCLUDE_MNEMONICS_YACC", file = outfile)
		print("/* INCLUDE_MNEMONICS_YACC */", file = outfile)
		print_mnemonics_yacc(yacc_instruction_list, file = outfile)

		print("@store INCLUDE_MNEMONICS_PATTERNS", file = outfile)
		print(f"/* INCLUDE_MNEMONICS_PATTERNS */", file = outfile)
		print_mnemonics_patterns('m6800', yacc_instruction_list, m6800_instruction_dict, file = outfile)
		print_mnemonics_patterns('m6809', yacc_instruction_list, m6809_instruction_dict, file = outfile)

		print("@store INCLUDE_EMULATION_TABLES", file = outfile)
		print(f"/* INCLUDE_EMULATION_TABLES */", file = outfile)
		print_emulation_table('m6800', m6800_instruction_matrix, m6809 = False, file = outfile)
		print_emulation_table('m6809', m6809_instruction_matrix, m6809 = True, file = outfile)

if __name__ == '__main__':
	main()

