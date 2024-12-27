#ifndef _6809_H
#define _6809_H

#include <stdbool.h>
#include "asm.h"

enum
{
	REG_D = 0,
	REG_X = 1,
	REG_Y = 2,
	REG_U = 3,
	REG_S = 4,
	REG_PC = 5,
	REG_A = 8,
	REG_B = 9,
	REG_CC = 10,
	REG_DP = 11,
};

enum
{
	MNEM_NONE,

@INCLUDE_MNEMONICS_YACC
};

enum
{
	OPD_NONE,
	OPD_IMMB,
	OPD_IMMW,
	OPD_DIR,
	OPD_IND,
	OPD_EXT,
	OPD_RELB,
	OPD_RELW,
	OPD_REG2,
	OPD_REGLIST,
	_OPD_TYPE_COUNT,

	OPD_EXPRESSION = 0,
};

typedef struct m68_operand m68_operand_t;
struct m68_operand
{
	expression_t * parameter;
	int type;
	int idx;
	int generated_type;
	int generated_idx;
};

typedef struct operand operand_t;

typedef struct m68_instruction m68_instruction_t;
struct m68_instruction
{
	instruction_t * next;
	size_t offset, next_offset;
	size_t size;
	mnemonic_t mnem;
	int count;
	m68_operand_t * opd[2];

	bool m6809;
	int disp;
	int dispsize;
};

m68_operand_t * m68_operand_make(int type, int idx, expression_t * parameter);
#define operand_make m68_operand_make

operand_t * m68_operand_expression(expression_t * parameter);
#define operand_expression m68_operand_expression

m68_instruction_t * m68_instruction_create(mnemonic_t mnem, size_t count, m68_operand_t * opd1, m68_operand_t * opd2);
m68_instruction_t * m68_instruction_create1(mnemonic_t mnem, m68_operand_t * opd1);

#define operand_t m68_operand_t

#endif /* _6809_H */
