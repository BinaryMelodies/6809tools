#ifndef _ASM_H
#define _ASM_H

typedef enum cpu_type
{
	CPU_UNSET,
#if 0
	CPU_M65,
	CPU_Z80,
#endif
	CPU_M68,
} cpu_type_t;
extern cpu_type_t current_cpu;

enum
{
	MASK_SIZE = 0xFF,
	FLAG_LITTLE_ENDIAN = 0x100,
	FLAG_BIG_ENDIAN = 0x200,

	MASK_SIZE_AND_BYTE_ORDER = MASK_SIZE | FLAG_LITTLE_ENDIAN | FLAG_BIG_ENDIAN,
};

enum process_state
{
	PROCESS_PRERUN,
	PROCESS_CALCULATE,
	PROCESS_GENERATE,
};
extern enum process_state process_state;

typedef enum mnemonic mnemonic_t;
enum mnemonic
{
	DIR_EOF = 0,

	// include other mnemonics as needed

	DIR_DATA = -0x10000,
	_DIR_FIRST = DIR_DATA - 1,

	DIR_ORG = -2,
	DIR_DEFINE = -1,
};

typedef struct expression expression_t;
struct expression
{
	enum
	{
		EXP_NOT = '!',
		EXP_MOD = '%',
		EXP_BITAND = '&',
		EXP_MUL = '*',
		EXP_ADD = '+',
		EXP_SUB = '-',
		EXP_DIV = '/',
		EXP_LT = '<',
		EXP_GT = '>',
		EXP_BITXOR = '^',
		EXP_BITOR = '|',
		EXP_BITNOT = '~',

		EXP_INT = 128,
		EXP_ID,
		EXP_STR,

		EXP_HERE, /* . * */

		EXP_ALIGN,
		EXP_PAREN, /* ( ) */
		EXP_PLUS,
		EXP_MINUS,
		EXP_AND, /* && */
		EXP_OR, /* || */
		EXP_NE, /* != */
		EXP_EQ, /* == */
		EXP_LE, /* <= */
		EXP_GE, /* >= */
		EXP_SHL, /* << */
		EXP_SHR, /* >> */
		EXP_LOW, /* < */
		EXP_HIGH, /* < */
	} type;
	union
	{
		int i;
		char * s;
		expression_t * x[2];
	};
};

expression_t * expression_make(int type);
expression_t * expression_identifier(char * s);
expression_t * expression_string(char * s);
expression_t * expression_integer(long i);
expression_t * expression_unary(int type, expression_t * exp);
expression_t * expression_binary(int type, expression_t * exp1, expression_t * exp2);

#define IGNORE 0

typedef struct operand operand_t;
struct operand
{
	expression_t * parameter;
};

typedef struct instruction instruction_t;
struct instruction
{
	instruction_t * next;
	size_t offset, next_offset;
	size_t size;
	mnemonic_t mnem;
	int count;
	operand_t * opd[2];
};

void instruction_stream_add(instruction_t * instruction);
void instruction_initialize(instruction_t * instruction, mnemonic_t mnem, size_t count, operand_t * opd1, operand_t * opd2);

instruction_t * instruction_stream_reposition(expression_t * parameter);
instruction_t * instruction_stream_define(char * name, expression_t * value);
instruction_t * instruction_stream_label(char * name);
instruction_t * instruction_stream_data(int size_and_byte_order, expression_t * value);
instruction_t * instruction_stream_string(int size_and_byte_order, char * value);
instruction_t * instruction_stream_directive(int dir);
instruction_t * instruction_stream_set_entry(expression_t * entry);

long evaluate_expression(size_t instr_offset, expression_t * expression);

void putbyte(int v);
void putword16le(int v);
void putword16be(int v);
void skip(size_t count);

#endif /* _ASM_H */
