
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "6809lib.h"

#define DEBUG(cpu, ...) do { if((cpu)->debug) fprintf(stderr, __VA_ARGS__); } while(0)

static uint8_t memory[65536];

uint8_t m6809_read_byte(uint16_t address)
{
	return memory[address & 0xFFFF];
}

void m6809_write_byte(uint16_t address, uint8_t value)
{
	memory[address & 0xFFFF] = value;
}

uint16_t m6809_read_word(uint16_t address)
{
	return (m6809_read_byte(address) << 8) | m6809_read_byte(address + 1);
}

void m6809_write_word(uint16_t address, uint16_t value)
{
	m6809_write_byte(address,     value >> 8);
	m6809_write_byte(address + 1, value);
}

static const char m6809_index_regname[] = "xyus";

static inline uint16_t m6809_index(m6809_t * cpu, uint8_t index)
{
	uint16_t address = 0;
	int alt = 0;
	bool check_indirection = true;
	bool check_register = true;
	if(!(index & 0x80))
	{
		address = index & 0x10 ? index | -0x20 : index & 0x0F;
		DEBUG(cpu, "$%X,%c", address, m6809_index_regname[(index >> 5) & 3]);
		check_indirection = false;
	}
	else
	{
		if((index & 0x10))
			DEBUG(cpu, "[");
		switch((index & 0xF))
		{
		case 0x0:
			DEBUG(cpu, ",%c+", m6809_index_regname[(index >> 5) & 3]);
			alt = 1;
			break;
		case 0x1:
			DEBUG(cpu, ",%c++", m6809_index_regname[(index >> 5) & 3]);
			alt = 2;
			break;
		case 0x2:
			DEBUG(cpu, ",-%c", m6809_index_regname[(index >> 5) & 3]);
			alt = address = -1;
			break;
		case 0x3:
			DEBUG(cpu, ",--%c", m6809_index_regname[(index >> 5) & 3]);
			alt = address = -2;
			break;
		case 0x4:
			DEBUG(cpu, ",%c", m6809_index_regname[(index >> 5) & 3]);
			break;
		case 0x5:
			DEBUG(cpu, "b,%c", m6809_index_regname[(index >> 5) & 3]);
			address = (int8_t)GETB(cpu);
			break;
		case 0x6:
			DEBUG(cpu, "a,%c", m6809_index_regname[(index >> 5) & 3]);
			address = (int8_t)GETA(cpu);
			break;
		case 0x8:
			address = (int8_t)FETCH(cpu);
			DEBUG(cpu, "$%X,%c", address, m6809_index_regname[(index >> 5) & 3]);
			break;
		case 0x9:
			address = FETCH(cpu) << 8;
			address |= FETCH(cpu);
			DEBUG(cpu, "$%X,%c", address, m6809_index_regname[(index >> 5) & 3]);
			break;
		case 0xB:
			address = cpu->d;
			DEBUG(cpu, "d,%c", m6809_index_regname[(index >> 5) & 3]);
			break;
		case 0xC:
			address = (int8_t)FETCH(cpu);
			DEBUG(cpu, "$%X,pcr", address);
			address += cpu->pc;
			check_register = false;
			break;
		case 0xD:
			address = FETCH(cpu) << 8;
			address += FETCH(cpu);
			DEBUG(cpu, "$%X,pcr", address);
			address += cpu->pc;
			check_register = false;
			break;
		case 0xF:
			address = FETCH(cpu) << 8;
			address += FETCH(cpu);
			DEBUG(cpu, ",$%X", address);
			check_register = false;
			break;
		}
		if((index & 0x10))
			DEBUG(cpu, "]");
	}
	if(check_register)
	{
		switch(((index >> 5) & 3))
		{
		case 0:
			address += cpu->x;
			cpu->x += alt;
			break;
		case 1:
			address += cpu->y;
			cpu->y += alt;
			break;
		case 2:
			address += cpu->u;
			cpu->u += alt;
			break;
		case 3:
			address += cpu->s;
			cpu->s += alt;
			break;
		}
	}
	if(check_indirection && (index & 0x10))
	{
		address = m6809_read_word(address);
	}
	return address;
}

static void m6809_test(m6809_t * cpu, uint8_t a)
{
	if(a == 0)
	{
		cpu->cc |= CC_Z;
	}
	else
	{
		cpu->cc &= ~CC_Z;
	}
	if((a & 0x80))
	{
		cpu->cc |= CC_N;
	}
	else
	{
		cpu->cc &= ~CC_N;
	}
}

static void m6809_testw(m6809_t * cpu, uint16_t a)
{
	if(a == 0)
	{
		cpu->cc |= CC_Z;
	}
	else
	{
		cpu->cc &= ~CC_Z;
	}
	if((a & 0x8000))
	{
		cpu->cc |= CC_N;
	}
	else
	{
		cpu->cc &= ~CC_N;
	}
}

static uint8_t m6809_adc(m6809_t * cpu, uint8_t a, uint8_t b, uint8_t c)
{
	int16_t result = (int8_t)a + (int8_t)b + c;
	if(((result ^ a ^ b) & 0x100))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if((result ^ (result >> 1)) & 0x80)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	if((result ^ a ^ b) & 0x10)
	{
		cpu->cc |= CC_H;
	}
	else
	{
		cpu->cc &= ~CC_H;
	}
	return result;
}

static uint8_t m6809_sbc(m6809_t * cpu, uint8_t a, uint8_t b, uint8_t c)
{
	int16_t result = (int8_t)a - (int8_t)b - c;
	if(!((result ^ a ^ ~b) & 0x100))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if((result ^ (result >> 1)) & 0x80)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	if((result ^ a ^ ~b) & 0x10)
	{
		cpu->cc |= CC_H;
	}
	else
	{
		cpu->cc &= ~CC_H;
	}
	return result;
}

static uint8_t m6809_neg(m6809_t * cpu, uint8_t value)
{
	return m6809_sbc(cpu, 0, value, 0);
}


static uint8_t m6809_inc_dec(m6809_t * cpu, uint8_t a, uint8_t b)
{
	int16_t result = (int8_t)a + (int8_t)b;
	if((result ^ (result >> 1)) & 0x80)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result;
}

static uint8_t m6809_asl(m6809_t * cpu, uint8_t a)
{
	int16_t result = (int8_t)a << 1;
	if((a & 0x80))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if(((cpu->cc ^ (result >> 7)) & 0x01))
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result & 0xFF;
}

static uint8_t m6809_asr(m6809_t * cpu, uint8_t a)
{
	int16_t result = (int8_t)a >> 1;
	if((a & 0x01))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if(((cpu->cc ^ (result >> 7)) & 0x01))
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result & 0xFF;
}

static uint8_t m6809_lsr(m6809_t * cpu, uint8_t a)
{
	int16_t result = (uint8_t)a >> 1;
	if((a & 0x01))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if(((cpu->cc ^ (result >> 7)) & 0x01))
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result & 0xFF;
}

static uint8_t m6809_rol(m6809_t * cpu, uint8_t a)
{
	int16_t result = ((int8_t)a << 1) | GETC(cpu);
	if((a & 0x80))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if(((cpu->cc ^ (result >> 7)) & 0x01))
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result & 0xFF;
}

static uint8_t m6809_ror(m6809_t * cpu, uint8_t a)
{
	int16_t result = ((uint8_t)a >> 1) | (GETC(cpu) << 7);
	if((a & 0x01))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if(((cpu->cc ^ (result >> 7)) & 0x01))
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
	return result & 0xFF;
}

static uint16_t m6809_addw(m6809_t * cpu, uint16_t a, uint16_t b)
{
	int32_t result = (int16_t)a + (int16_t)b;
	if(((result ^ a ^ b) & 0x100))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if((result ^ (result >> 1)) & 0x8000)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	if(result == 0)
	{
		cpu->cc |= CC_Z;
	}
	else
	{
		cpu->cc &= ~CC_Z;
	}
	if((result & 0x8000))
	{
		cpu->cc |= CC_N;
	}
	else
	{
		cpu->cc &= ~CC_N;
	}
	return result;
}

static uint16_t m6809_subw(m6809_t * cpu, uint16_t a, uint16_t b)
{
	int32_t result = (int16_t)a - (int16_t)b;
	if(!((result ^ a ^ ~b) & 0x100))
	{
		cpu->cc |= CC_C;
	}
	else
	{
		cpu->cc &= ~CC_C;
	}
	if((result ^ (result >> 1)) & 0x80)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	if(result == 0)
	{
		cpu->cc |= CC_Z;
	}
	else
	{
		cpu->cc &= ~CC_Z;
	}
	if((result & 0x8000))
	{
		cpu->cc |= CC_N;
	}
	else
	{
		cpu->cc &= ~CC_N;
	}
	return result;
}

#define OTHER_s u
#define OTHER_u s

#define PUSHM(S, cpu, data) do { \
	if(((data) & 0x80)) \
	{ \
		PUSHW(S, (cpu), (cpu)->pc); \
	} \
	if(((data) & 0x40)) \
	{ \
		PUSHW(S, (cpu), (cpu)->OTHER_##S); \
	} \
	if(((data) & 0x20)) \
	{ \
		PUSHW(S, (cpu), (cpu)->y); \
	} \
	if(((data) & 0x10)) \
	{ \
		PUSHW(S, (cpu), (cpu)->x); \
	} \
	if(((data) & 0x08)) \
	{ \
		PUSH(S, (cpu), (cpu)->dp); \
	} \
	if(((data) & 0x04)) \
	{ \
		PUSH(S, (cpu), (cpu)->d); \
	} \
	if(((data) & 0x02)) \
	{ \
		PUSH(S, (cpu), (cpu)->d >> 8); \
	} \
	if(((data) & 0x01)) \
	{ \
		PUSH(S, (cpu), (cpu)->cc); \
	} \
} while(0)

#define PULLM(S, cpu, data) do { \
	if(((data) & 0x01)) \
	{ \
		(cpu)->cc = PULL(S, (cpu)); \
	} \
	if(((data) & 0x06) == 0x06) \
	{ \
		(cpu)->d = PULLW(S, (cpu)); \
	} \
	else if(((data) & 0x02)) \
	{ \
		(cpu)->d = ((cpu)->d & 0xFF) | (PULL(S, (cpu)) << 8); \
	} \
	else if(((data) & 0x04)) \
	{ \
		(cpu)->d = ((cpu)->d & 0xFF00) | PULL(S, (cpu)); \
	} \
	if(((data) & 0x08)) \
	{ \
		(cpu)->dp = PULL(S, (cpu)); \
	} \
	if(((data) & 0x10)) \
	{ \
		(cpu)->x = PULLW(S, (cpu)); \
	} \
	if(((data) & 0x20)) \
	{ \
		(cpu)->y = PULLW(S, (cpu)); \
	} \
	if(((data) & 0x40)) \
	{ \
		(cpu)->OTHER_##S = PULLW(S, (cpu)); \
	} \
	if(((data) & 0x80)) \
	{ \
		(cpu)->pc = PULLW(S, (cpu)); \
	} \
} while(0)

#define UNDEFINED() fprintf(stderr, "Undefined opcode\n");

#define m6809_regsize(v) ((v) & 0x8 ? 1 : 2)

static const char * m6809_regname[] =
{
	"d", "x", "y", "u", "s", "pc", "_6", "_7",
	"a", "b", "cc", "dp", "_12", "_13", "_14", "_15"
};

static const char * m6809_stacks_regname[] =
{
	"cc", "a", "b", "dp", "x", "y", "u", "pc"
};

static const char * m6809_stacku_regname[] =
{
	"cc", "a", "b", "dp", "x", "y", "s", "pc"
};

static uint16_t m6809_read_register(m6809_t * cpu, int number)
{
	switch(number)
	{
	case 0x0:
		return cpu->d;
	case 0x1:
		return cpu->x;
	case 0x2:
		return cpu->y;
	case 0x3:
		return cpu->u;
	case 0x4:
		return cpu->s;
	case 0x5:
		return cpu->pc;
	case 0x8:
		return GETA(cpu);
	case 0x9:
		return GETB(cpu);
	case 0xA:
		return cpu->cc;
	case 0xB:
		return cpu->dp;
	default:
		UNDEFINED();
		return 0;
	}
}

static void m6809_write_register(m6809_t * cpu, int number, uint16_t value)
{
	switch(number)
	{
	case 0x0:
		cpu->d = value;
		break;
	case 0x1:
		cpu->x = value;
		break;
	case 0x2:
		cpu->y = value;
		break;
	case 0x3:
		cpu->u = value;
		break;
	case 0x4:
		cpu->s = value;
		break;
	case 0x5:
		cpu->pc = value;
		break;
	case 0x8:
		SETA(cpu, value);
		break;
	case 0x9:
		SETB(cpu, value);
		break;
	case 0xA:
		cpu->cc = value;
		break;
	case 0xB:
		cpu->dp = value;
		break;
	default:
		UNDEFINED();
	}
}

static bool m6809_check_condition(m6809_t * cpu, uint8_t op)
{
	switch((op & 0xF))
	{
	default:
		/* never happens, silences warning */
	case 0x0:
		/* ra */
		return true;
	case 0x1:
		/* rn */
		return false;
	case 0x2:
		/* hi */
		return (cpu->cc & CC_Z) == 0 && (cpu->cc & CC_C) == 0;
	case 0x3:
		/* ls */
		return (cpu->cc & CC_Z) != 0 || (cpu->cc & CC_C) != 0;
	case 0x4:
		/* cc/hs */
		return (cpu->cc & CC_C) == 0;
	case 0x5:
		/* cs/lo */
		return (cpu->cc & CC_C) != 0;
	case 0x6:
		/* ne */
		return (cpu->cc & CC_Z) == 0;
	case 0x7:
		/* eq */
		return (cpu->cc & CC_Z) != 0;
	case 0x8:
		/* vc */
		return (cpu->cc & CC_V) == 0;
	case 0x9:
		/* vs */
		return (cpu->cc & CC_V) != 0;
	case 0xA:
		/* pl */
		return (cpu->cc & CC_N) == 0;
	case 0xB:
		/* mi */
		return (cpu->cc & CC_N) != 0;
	case 0xC:
		/* ge */
		return ((cpu->cc & CC_N) != 0) == ((cpu->cc & CC_V) != 0);
	case 0xD:
		/* lt */
		return ((cpu->cc & CC_N) != 0) != ((cpu->cc & CC_V) != 0);
	case 0xE:
		/* gt */
		return (cpu->cc & CC_Z) == 0 && ((cpu->cc & CC_N) != 0) == ((cpu->cc & CC_V) != 0);
	case 0xF:
		/* le */
		return (cpu->cc & CC_Z) != 0 || ((cpu->cc & CC_N) != 0) != ((cpu->cc & CC_V) != 0);
	}
}

static void m6809_dec_adj(m6809_t * cpu)
{
	uint16_t result = 0;
	if((cpu->d & 0xF) > 0x9 || (cpu->cc & CC_H))
		result += 0x6;
	if((cpu->d & 0xF0) > 0x90 || (cpu->cc & CC_C) || ((cpu->d & 0xFF) > 0x99))
		result += 0x60;
	if((cpu->d & 0xF0) > 0x90)
		cpu->cc |= CC_C;
	result += (uint8_t)(cpu->d) & 0xFF;
	cpu->d = (cpu->d & 0xFF00) | (result & 0xFF);
	if((result ^ (result >> 1)) & 0x80)
	{
		cpu->cc |= CC_V;
	}
	else
	{
		cpu->cc &= ~CC_V;
	}
	m6809_test(cpu, result);
}

static void m6809_begin_interrupt(m6809_t * cpu)
{
	PUSHW(s, cpu, cpu->pc);
	if(cpu->emu6800)
	{
		PUSHW(s, cpu, cpu->x);
		PUSH(s, cpu, cpu->d);
		PUSH(s, cpu, cpu->d >> 8);
	}
	else
	{
		PUSHW(s, cpu, cpu->u);
		PUSHW(s, cpu, cpu->y);
		PUSHW(s, cpu, cpu->x);
		PUSH(s, cpu, cpu->dp);
		PUSHW(s, cpu, cpu->d);
	}
	PUSH(s, cpu, cpu->cc);
}

static void m6809_return_interrupt(m6809_t * cpu)
{
	cpu->cc = PULL(s, cpu);
	if(cpu->emu6800 || (cpu->cc & CC_E))
	{
		cpu->d = PULL(s, cpu) << 8;
		cpu->d |= PULL(s, cpu);
		cpu->x = PULLW(s, cpu);
	}
	else if((cpu->cc & CC_E))
	{
		cpu->dp = PULL(s, cpu);
		cpu->d = PULLW(s, cpu);
		cpu->x = PULLW(s, cpu);
		cpu->y = PULLW(s, cpu);
		cpu->u = PULLW(s, cpu);
	}
	cpu->pc = PULLW(s, cpu);
}

static void m6809_do_interrupt(m6809_t * cpu, int vector)
{
	if(vector == IV_FIRQ)
	{
		cpu->cc &= ~CC_E;
		PUSHW(s, cpu, cpu->pc);
		PUSH(s, cpu, cpu->cc);
	}
	else
	{
		cpu->cc |= CC_E;
		m6809_begin_interrupt(cpu);
	}
	if(vector == IV_FIRQ || vector == IV_IRQ || vector == IV_SWI || vector == IV_NMI
	|| (cpu->emu6800 && vector == IV_RESET))
	{
		cpu->cc |= CC_I;
	}
	if(!cpu->emu6800 && (vector == IV_FIRQ || vector == IV_SWI || vector == IV_NMI))
	{
		cpu->cc |= CC_F;
	}
	cpu->pc = m6809_read_word(vector);
}

static bool m6809_can_service(m6809_t * cpu, int vector)
{
	return !((vector != IV_NMI && (cpu->cc & CC_I)) || (vector == IV_FIRQ && (cpu->cc & CC_F)));
}

void m6809_hardware_interrupt(m6809_t * cpu, int vector)
{
	if(!m6809_can_service(cpu, vector))
		return;
	m6809_do_interrupt(cpu, vector);
}

static void m6809_wait_interrupt(m6809_t * cpu)
{
	/* TODO */
	/*
	for(;;)
	{
		int vector = m6809_get_interrupt(cpu);
		if(m6809_can_service(cpu, vector))
		{
			m6809_hardware_interrupt(cpu, vector);
			return;
		}
	}
	*/
}

static void m6809_sync_interrupt(m6809_t * cpu)
{
	/* TODO */
	/*
	int vector = m6809_get_interrupt(cpu);
	m6809_hardware_interrupt(cpu, vector);
	*/
}

#define m6809_reset(cpu) m6809_do_interrupt((cpu), IV_RESET)

#define DIRECT(cpu) (((cpu)->dp << 8) | FETCH(cpu))
#define INDEXED(cpu) ((cpu)->x + FETCH(cpu))

@INCLUDE_EMULATION_TABLES

void m6809_step(m6809_t * cpu)
{
	if(cpu->emu6800)
	{
		do_m6800_step(cpu);
	}
	else
	{
		do_m6809_step(cpu);
	}
}

