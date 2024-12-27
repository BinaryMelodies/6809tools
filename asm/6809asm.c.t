
#include <stdio.h>
#include <stdlib.h>
#include "asm.h"
#include "6809asm.h"

#undef operand_t

m68_operand_t * m68_operand_make(int type, int idx, expression_t * parameter)
{
	m68_operand_t * operand = malloc(sizeof(m68_operand_t));
	operand->type = type;
	operand->idx = idx;
	operand->parameter = parameter;
	return operand;
}

operand_t * m68_operand_expression(expression_t * parameter)
{
	return (operand_t *)m68_operand_make(OPD_EXPRESSION, 0, parameter);
}

m68_instruction_t * m68_instruction_create(mnemonic_t mnem, size_t count, m68_operand_t * opd1, m68_operand_t * opd2)
{
	m68_instruction_t * instruction = malloc(sizeof(m68_instruction_t));
	instruction_initialize((instruction_t *)instruction, mnem, count, (operand_t *)opd1, (operand_t *)opd2);
	instruction_stream_add((instruction_t *)instruction);
	return instruction;
}

m68_instruction_t * m68_instruction_create1(mnemonic_t mnem, m68_operand_t * opd1)
{
	return m68_instruction_create(mnem, 1, opd1, NULL);
}

instruction_t * m68_instruction_make(mnemonic_t mnem, size_t count, operand_t * opd1, operand_t * opd2)
{
	return (instruction_t *)m68_instruction_create(mnem, count, (m68_operand_t *)opd1, (m68_operand_t *)opd2);
}

void m68_restart_generation(void)
{
}

int reg_stack_flag[] =
{
	[REG_D] = 0x06,
	[REG_X] = 0x10,
	[REG_Y] = 0x20,
	[REG_U] = 0x40,
	[REG_S] = 0x40,
	[REG_PC] = 0x80,
	[REG_A] = 0x02,
	[REG_B] = 0x04,
	[REG_CC] = 0x01,
	[REG_DP] = 0x08,
};

#define UNDEF 0x02

@INCLUDE_MNEMONICS_PATTERNS

int get_instruction_length(int pattern)
{
	if(pattern < 0x100)
		return 1;
	else
		return 2;
}

int m68_get_operation_size(m68_instruction_t * ins, int opcode)
{
	int size = get_instruction_length(opcode);
	switch(ins->opd[0]->generated_type)
	{
	case OPD_NONE:
		break;
	case OPD_IMMB:
		size += 1;
		break;
	case OPD_IMMW:
		size += 2;
		break;
	case OPD_DIR:
		size += 1;
		break;
	case OPD_IND:
		if(ins->m6809)
		{
			size += 1 + ins->dispsize;
		}
		else
		{
			size += 1;
		}
		break;
	case OPD_EXT:
		size += 2;
		break;
	case OPD_RELB:
		size += 1;
		break;
	case OPD_RELW:
		size += 2;
		break;
	case OPD_REG2:
	case OPD_REGLIST:
		size += 1;
		break;
	}
	return size;
}

void m68_generate_template(m68_instruction_t * ins, int opcode, bool m6809)
{
	switch(get_instruction_length(opcode))
	{
	case 1:
		putbyte(opcode);
		break;
	case 2:
		putword16be(opcode);
		break;
	}
	switch(ins->opd[0]->generated_type)
	{
	case OPD_NONE:
		break;
	case OPD_IMMB:
		putbyte(ins->disp);
		break;
	case OPD_IMMW:
		putword16be(ins->disp);
		break;
	case OPD_DIR:
		putbyte(ins->disp);
		break;
	case OPD_IND:
		if(m6809)
		{
			putbyte(ins->opd[0]->generated_idx);
		}
		switch(ins->dispsize)
		{
		case 1:
			putbyte(ins->disp);
			break;
		case 2:
			putword16be(ins->disp);
			break;
		}
		break;
	case OPD_EXT:
		putword16be(ins->disp);
		break;
	case OPD_RELB:
		putbyte(ins->disp);
		break;
	case OPD_RELW:
		putword16be(ins->disp);
		break;
	case OPD_REG2:
	case OPD_REGLIST:
		putbyte(ins->opd[0]->idx);
		break;
	}
}

void m6809_get_actual_index(size_t offset, m68_instruction_t * ins, int inslen)
{
	ins->opd[0]->generated_idx = ins->opd[0]->idx;
	ins->opd[0]->idx |= 0x80;
	switch((ins->opd[0]->generated_idx & 0x0F))
	{
	case 0x04:
		/* n,R */
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
		if(process_state == PROCESS_PRERUN || ins->disp == 0)
		{
			ins->dispsize = 0;
		}
		else if(!(ins->opd[0]->generated_idx & 0x10) && -0x10 <= ins->disp && ins->disp <= 0x0F)
		{
			ins->opd[0]->generated_idx = (ins->opd[0]->generated_idx & 0x60) | (ins->disp & 0x1F);
			ins->disp = 0;
			ins->dispsize = 0;
		}
		else if(-0x80 <= ins->disp && ins->disp <= 0x7F)
		{
			ins->opd[0]->generated_idx = (ins->opd[0]->generated_idx & 0xF0) | 0x08;
			ins->dispsize = 1;
		}
		else
		{
			ins->opd[0]->generated_idx = (ins->opd[0]->generated_idx & 0xF0) | 0x09;
			ins->dispsize = 2;
		}
		break;
	case 0x0C:
		/* n,PCR */
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter) - offset;
		if(process_state == PROCESS_PRERUN || (-0x80 <= (ins->disp - inslen - 1) && (ins->disp - inslen - 1) <= 0x7F))
		{
			ins->dispsize = 1;
			ins->disp -= inslen + 1;
		}
		else
		{
			ins->opd[0]->generated_idx = ins->opd[0]->generated_idx | 1;
			ins->dispsize = 2;
			ins->disp -= inslen + 2;
		}
		break;
	case 0x0F:
		/* [n] */
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
		ins->dispsize = 2;
		break;
	default:
		ins->dispsize = 0;
		break;
	}
}

int match_mode(size_t offset, m68_instruction_t * ins, unsigned * patterns)
{
	ins->opd[0]->generated_type = ins->opd[0]->type;
	switch(ins->opd[0]->type)
	{
	case OPD_IMMB:
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
		if(patterns[OPD_IMMB] != UNDEF)
		{
			ins->dispsize = 1;
		}
		else
		{
			ins->opd[0]->generated_type = OPD_IMMW;
			ins->dispsize = 2;
		}
		break;
	case OPD_IND:
		if(ins->m6809)
		{
			m6809_get_actual_index(offset, ins, get_instruction_length(patterns[OPD_IND]) + 1);
		}
		else
		{
			if(process_state != PROCESS_PRERUN)
				ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
			ins->dispsize = 1;
		}
		break;
	case OPD_RELB:
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter) - offset;
		if(patterns[OPD_RELB] != UNDEF)
		{
			int disp2 = ins->disp - get_instruction_length(patterns[OPD_RELB]) - 1;
			if(process_state == PROCESS_PRERUN || (-0x80 <= disp2 && disp2 <= 0x7F))
			{
				if(process_state != PROCESS_PRERUN)
					ins->disp = disp2;
				ins->dispsize = 1;
			}
			else if(patterns[OPD_RELW] == UNDEF)
			{
				fprintf(stderr, "Offset out of range\n");
			}
			else
			{
				ins->opd[0]->generated_type = OPD_RELW;
				ins->disp -= get_instruction_length(patterns[OPD_RELW]) + 2;
				ins->dispsize = 2;
			}
		}
		else
		{
			ins->opd[0]->generated_type = OPD_RELW;
			ins->disp -= get_instruction_length(patterns[OPD_RELW]) + 2;
			ins->dispsize = 2;
		}
		break;
	case OPD_DIR:
		if(!ins->m6809)
		{
			if(process_state != PROCESS_PRERUN)
				ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
			if(patterns[OPD_DIR] != UNDEF && (process_state == PROCESS_PRERUN || (0 <= ins->disp && ins->disp <= 0xFF)))
			{
				ins->dispsize = 1;
			}
			else
			{
				ins->opd[0]->generated_type = OPD_EXT;
				ins->dispsize = 2;
			}
			break;
		}
	case OPD_EXT:
		if(process_state != PROCESS_PRERUN)
			ins->disp = evaluate_expression(offset, ins->opd[0]->parameter);
		ins->dispsize = ins->opd[0]->type == OPD_DIR ? 1 : 2;
		break;
	}
	if(patterns[ins->opd[0]->generated_type] == UNDEF)
	{
		fprintf(stderr, "Internal error\n");
	}
	return patterns[ins->opd[0]->generated_type];
}

int match_mode_either(size_t offset, m68_instruction_t * ins)
{
	return match_mode(offset, ins, ins->m6809 ? m6809_patterns[ins->mnem] : m6800_patterns[ins->mnem]);
}

void m68_process_instruction(size_t offset, instruction_t * instruction)
{
	m68_instruction_t * ins = (m68_instruction_t *)instruction;
	int opcode = match_mode_either(offset, ins);
	if(process_state != PROCESS_GENERATE)
		instruction->size = m68_get_operation_size(ins, opcode);
	else
		m68_generate_template(ins, opcode, ins->m6809);
}

