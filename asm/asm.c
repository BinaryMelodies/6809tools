
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "asm.h"

extern int m68_parse(void);
#define parse m68_parse

/* creates an operand that contains a basic expression */
extern operand_t * m68_operand_expression(expression_t * parameter);
#define cpu_operand_expression m68_operand_expression

extern void m68_restart_generation(void);
#define cpu_restart_generation m68_restart_generation

extern void m68_process_instruction(size_t offset, instruction_t * instruction);
#define cpu_process_instruction m68_process_instruction

instruction_t * m68_instruction_make(mnemonic_t mnem, size_t count, operand_t * opd1, operand_t * opd2);
#define cpu_instruction_make m68_instruction_make

expression_t * expression_make(int type)
{
	expression_t * expression = malloc(sizeof(expression_t));
	expression->type = type;
	return expression;
}

expression_t * expression_identifier(char * s)
{
	expression_t * expression = expression_make(EXP_ID);
	expression->s = s;
	return expression;
}

expression_t * expression_string(char * s)
{
	expression_t * expression = expression_make(EXP_STR);
	expression->s = s;
	return expression;
}

expression_t * expression_integer(long i)
{
	expression_t * expression = expression_make(EXP_INT);
	expression->i = i;
	return expression;
}

expression_t * expression_unary(int type, expression_t * exp)
{
	expression_t * expression = expression_make(type);
	expression->x[0] = exp;
	return expression;
}

expression_t * expression_binary(int type, expression_t * exp1, expression_t * exp2)
{
	expression_t * expression = expression_make(type);
	expression->x[0] = exp1;
	expression->x[1] = exp2;
	return expression;
}

static instruction_t * instruction_stream;
static instruction_t ** instruction_last = &instruction_stream;

void instruction_stream_add(instruction_t * instruction)
{
	instruction->next = NULL;
	*instruction_last = instruction;
	instruction_last = &instruction->next;
}

void instruction_initialize(instruction_t * instruction, mnemonic_t mnem, size_t count, operand_t * opd1, operand_t * opd2)
{
	instruction->offset = 0;
	instruction->size = 0;

	instruction->mnem = mnem;
	instruction->count = count;
	instruction->opd[0] = opd1;
	instruction->opd[1] = opd2;
}

instruction_t * default_instruction_make(mnemonic_t mnem, size_t count, operand_t * opd1, operand_t * opd2)
{
	instruction_t * instruction = malloc(sizeof(instruction_t));
	instruction_initialize(instruction, mnem, count, opd1, opd2);
	instruction_stream_add(instruction);
	return instruction;
}

instruction_t * instruction_stream_reposition(expression_t * parameter)
{
	return (*cpu_instruction_make)(DIR_ORG, 1, (*cpu_operand_expression)(parameter), NULL);
}

instruction_t * instruction_stream_define(char * name, expression_t * value)
{
	return (*cpu_instruction_make)(DIR_DEFINE, 2, (*cpu_operand_expression)(expression_identifier(name)), (*cpu_operand_expression)(value));
}

instruction_t * instruction_stream_label(char * name)
{
	return instruction_stream_define(name, expression_make(EXP_HERE));
}

instruction_t * instruction_stream_data(int size_and_byte_order, expression_t * value)
{
	return (*cpu_instruction_make)(DIR_DATA | size_and_byte_order, 1, (*cpu_operand_expression)(value), NULL);
}

instruction_t * instruction_stream_string(int size_and_byte_order, char * value)
{
	return instruction_stream_data(size_and_byte_order, expression_string(value));
}

instruction_t * instruction_stream_directive(int dir)
{
	return (*cpu_instruction_make)(dir, 0, NULL, NULL);
}

instruction_t * start_address;

instruction_t * instruction_stream_set_entry(expression_t * entry)
{
	if(start_address != NULL)
	{
		fprintf(stderr, "Error: start address already set, ignoring\n");
		return NULL;
	}
	return start_address = instruction_stream_define(NULL, expression_make(EXP_HERE)); // TODO: this is hacky, <null>:
}

////

typedef struct definition definition_t;
struct definition
{
	char * name;
	instruction_t * declaration;
	definition_t * next;
};

static definition_t * definitions;
static definition_t ** last_definition = &definitions;

void define(char * name, instruction_t * declaration)
{
	// TODO: check for no redefinition
	definition_t * definition = malloc(sizeof(definition_t));
	definition->name = name;
	definition->declaration = declaration;
	definition->next = NULL;
	*last_definition = definition;
	last_definition = &definition->next;
}

instruction_t * lookup(const char * name)
{
	for(definition_t * definition = definitions; definition != NULL; definition = definition->next)
	{
		if(strcmp(definition->name, name) == 0)
			return definition->declaration;
	}
	return NULL;
}

static long align_to(long value, long boundary)
{
	value += boundary - 1;
	return value - value % boundary;
}

long evaluate_expression(size_t instr_offset, expression_t * expression)
{
	if(expression == NULL)
		return 0;
	switch(expression->type)
	{
	case EXP_ALIGN:
		return align_to(evaluate_expression(instr_offset, expression->x[0]), evaluate_expression(instr_offset, expression->x[1]));
	case '~':
		return ~evaluate_expression(instr_offset, expression->x[0]);
	case '!':
		return !evaluate_expression(instr_offset, expression->x[0]);
	case '*':
		return evaluate_expression(instr_offset, expression->x[0]) * evaluate_expression(instr_offset, expression->x[1]);
	case '/':
		return evaluate_expression(instr_offset, expression->x[0]) / evaluate_expression(instr_offset, expression->x[1]);
	case '%':
		return evaluate_expression(instr_offset, expression->x[0]) % evaluate_expression(instr_offset, expression->x[1]);
	case '+':
		return evaluate_expression(instr_offset, expression->x[0]) + evaluate_expression(instr_offset, expression->x[1]);
	case '-':
		return evaluate_expression(instr_offset, expression->x[0]) - evaluate_expression(instr_offset, expression->x[1]);
	case '&':
		return evaluate_expression(instr_offset, expression->x[0]) & evaluate_expression(instr_offset, expression->x[1]);
	case '^':
		return evaluate_expression(instr_offset, expression->x[0]) ^ evaluate_expression(instr_offset, expression->x[1]);
	case '|':
		return evaluate_expression(instr_offset, expression->x[0]) | evaluate_expression(instr_offset, expression->x[1]);
	case '<':
		return evaluate_expression(instr_offset, expression->x[0]) < evaluate_expression(instr_offset, expression->x[1]);
	case '>':
		return evaluate_expression(instr_offset, expression->x[0]) > evaluate_expression(instr_offset, expression->x[1]);
	case EXP_INT:
		return expression->i;
	case EXP_ID:
		{
			instruction_t * instr = lookup(expression->s);
			long value = evaluate_expression(instr->offset, instr->opd[1]->parameter);
			return value;
		}

	case EXP_STR:
		assert(false);

	case EXP_HERE:
		return instr_offset;

	case EXP_PAREN:
	case EXP_PLUS:
		return evaluate_expression(instr_offset, expression->x[0]);
	case EXP_MINUS:
		return -evaluate_expression(instr_offset, expression->x[0]);
	case EXP_AND:
		return (evaluate_expression(instr_offset, expression->x[0]) != 0) & (evaluate_expression(instr_offset, expression->x[1]) != 0);
	case EXP_OR:
		return (evaluate_expression(instr_offset, expression->x[0]) != 0) | (evaluate_expression(instr_offset, expression->x[1]) != 0);
	case EXP_NE:
		return evaluate_expression(instr_offset, expression->x[0]) != evaluate_expression(instr_offset, expression->x[1]);
	case EXP_EQ:
		return evaluate_expression(instr_offset, expression->x[0]) == evaluate_expression(instr_offset, expression->x[1]);
	case EXP_LE:
		return evaluate_expression(instr_offset, expression->x[0]) <= evaluate_expression(instr_offset, expression->x[1]);
	case EXP_GE:
		return evaluate_expression(instr_offset, expression->x[0]) >= evaluate_expression(instr_offset, expression->x[1]);
	case EXP_SHL:
		return evaluate_expression(instr_offset, expression->x[0]) << evaluate_expression(instr_offset, expression->x[1]);
	case EXP_SHR:
		return evaluate_expression(instr_offset, expression->x[0]) >> evaluate_expression(instr_offset, expression->x[1]);
	case EXP_LOW:
		return evaluate_expression(instr_offset, expression->x[0]) & 0xFF;
	case EXP_HIGH:
		return evaluate_expression(instr_offset, expression->x[0]) >> 8;
	default:
		assert(false);
	}
}

enum process_state process_state;

cpu_type_t current_cpu;

FILE * output_file = NULL;
unsigned output_address = 0;

enum
{
	FMT_FLAT,
	FMT_FLEX_CMD,
	FMT_DEBUG,
} output_format;

struct cmd_record
{
	uint8_t length;
	uint16_t address;
	uint8_t content[256];
} cmd_record;

static void cmd_record_print(void)
{
	fputc(0x02, output_file);
	fputc(cmd_record.address >> 8, output_file);
	fputc(cmd_record.address, output_file);
	fputc(cmd_record.length, output_file);
	for(int i = 0; i < cmd_record.length; i++)
		fputc(cmd_record.content[i], output_file);
}

void setaddress(unsigned value)
{
	output_address = value;
}

void putbyte(int v)
{
	switch(output_format)
	{
	case FMT_FLAT:
		fputc(v, output_file);
		break;
	case FMT_FLEX_CMD:
		if(cmd_record.length >= 255 || cmd_record.address + cmd_record.length != output_address)
		{
			if(cmd_record.length != 0)
			{
				cmd_record_print();
			}
			cmd_record.length = 0;
			cmd_record.address = output_address;
		}
		cmd_record.content[cmd_record.length++] = v;
		break;
	case FMT_DEBUG:
		fprintf(stderr, "[%04X] %02X\n", output_address, v & 0xFF);
		break;
	}
	output_address += 1;
}

void putword16le(int v)
{
	putbyte(v);
	putbyte(v >> 8);
}

void putword16be(int v)
{
	putbyte(v >> 8);
	putbyte(v);
}

void skip(size_t count)
{
	// TODO: improve
	while(count-- != 0)
	{
		putbyte(0);
	}
}

void finish(void)
{
	switch(output_format)
	{
	case FMT_FLAT:
		fclose(output_file);
		break;
	case FMT_FLEX_CMD:
		if(cmd_record.length != 0)
		{
			cmd_record_print();
		}
		if(start_address != NULL)
		{
			int start = evaluate_expression(start_address->offset, start_address->opd[1]->parameter);
			fputc(0x16, output_file);
			fputc(start >> 8, output_file);
			fputc(start, output_file);
		}
		fclose(output_file);
		break;
	case FMT_DEBUG:
		break;
	}
}

void process_instruction(size_t offset, instruction_t * instruction)
{
	switch(instruction->mnem)
	{
	case DIR_EOF:
	case DIR_DEFINE:
		if(process_state != PROCESS_GENERATE)
			instruction->size = 0;
		break;
	case DIR_ORG:
		if(process_state != PROCESS_GENERATE)
			instruction->next_offset = evaluate_expression(offset, instruction->opd[0]->parameter);
		else
			setaddress(instruction->next_offset);
		return;
	default:
		if(instruction->mnem < 0 && instruction->mnem >= DIR_DATA)
		{
			// data
			if(process_state != PROCESS_GENERATE)
			{
				instruction->size = instruction->mnem & MASK_SIZE;
				if(instruction->opd[0]->parameter->type == EXP_STR)
				{
					size_t strsize = strlen(instruction->opd[0]->parameter->s) + instruction->size - 1;
					instruction->size = strsize - (strsize % instruction->size);
				}
			}
			else
			{
				if(instruction->opd[0]->parameter->type == EXP_STR)
				{
					size_t i;
					char * s = instruction->opd[0]->parameter->s;
					for(i = 0; s[i]; i++)
						putbyte(s[i]);
					skip(instruction->size - i);
				}
				else
				{
					switch((instruction->mnem & MASK_SIZE_AND_BYTE_ORDER))
					{
					case 1:
					case 1 | FLAG_LITTLE_ENDIAN:
					case 1 | FLAG_BIG_ENDIAN:
						putbyte(evaluate_expression(instruction->offset, instruction->opd[0]->parameter));
						break;
					case 2 | FLAG_LITTLE_ENDIAN:
						putword16le(evaluate_expression(instruction->offset, instruction->opd[0]->parameter));
						break;
					case 2 | FLAG_BIG_ENDIAN:
						putword16be(evaluate_expression(instruction->offset, instruction->opd[0]->parameter));
						break;
					}
				}
			}
		}
		else
		{
			// instruction
			(*cpu_process_instruction)(offset, instruction);
		}
		break;
	}
	if(process_state != PROCESS_GENERATE)
		instruction->next_offset = offset + instruction->size;
}

bool process_file(void)
{
	bool changed = true;
	size_t offset = 0;
	changed = false;
	(*cpu_restart_generation)();
	for(instruction_t * instr = instruction_stream; instr != NULL; instr = instr->next)
	{
		if(process_state == PROCESS_GENERATE)
			offset = instr->offset;
		process_instruction(offset, instr);
		if(instr->next != NULL)
			changed |= instr->next_offset != instr->next->offset;
		offset = instr->next_offset;
	}

	if(process_state != PROCESS_GENERATE)
	{
		for(instruction_t * instr = instruction_stream; instr != NULL && instr->next != NULL; instr = instr->next)
		{
			instr->next->offset = instr->next_offset;
		}
	}

	return changed;
}

int main(int argc, char * argv[])
{
	int argi;
	char * input_filename = NULL;
	char * output_filename = NULL;
	for(argi = 1; argi < argc; argi++)
	{
		if(argv[argi][0] == '-')
		{
			if(argv[argi][1] == 'm')
			{
				char * arg = &argv[argi][2];
				if(arg[0] == '\0' && argi + 1 < argc)
					arg = argv[++argi];
				if(strcasecmp(arg, "65") == 0
				|| strcasecmp(arg, "6502") == 0
				|| strcasecmp(arg, "m65") == 0
				|| strcasecmp(arg, "m6502") == 0)
				{
#if 0
					current_cpu = CPU_M65;
#endif
					fprintf(stderr, "6505 not supported\n");
					exit(1);
				}
				else if(strcasecmp(arg, "z80") == 0)
				{
#if 0
					current_cpu = CPU_Z80;
#endif
					fprintf(stderr, "Z80 not supported");
					exit(1);
				}
				else if(strcasecmp(arg, "68") == 0
				|| strcasecmp(arg, "6800") == 0
				|| strcasecmp(arg, "m68") == 0
				|| strcasecmp(arg, "m6800") == 0
				|| strcasecmp(arg, "69") == 0
				|| strcasecmp(arg, "6809") == 0
				|| strcasecmp(arg, "m69") == 0
				|| strcasecmp(arg, "m6809") == 0)
				{
					current_cpu = CPU_M68;
				}
				else
				{
					fprintf(stderr, "Unknown CPU architecture: `%s'\n", arg);
				}
			}
			else if(argv[argi][1] == 'o')
			{
				char * arg = &argv[argi][2];
				if(arg[0] == '\0' && argi + 1 < argc)
					arg = argv[++argi];
				if(arg[0] == '\0')
				{
					fprintf(stderr, "No output file added\n");
				}
				else if(output_filename != NULL)
				{
					fprintf(stderr, "Multiple output files provided, ignoring `%s'\n", arg);
				}
				else
				{
					output_filename = arg;
				}
			}
			else if(argv[argi][1] == 'f')
			{
				char * arg = &argv[argi][2];
				if(arg[0] == '\0' && argi + 1 < argc)
					arg = argv[++argi];
				if(strcasecmp(arg, "flat") == 0
				|| strcasecmp(arg, "bin") == 0)
				{
					output_format = FMT_FLAT;
				}
				else if(strcasecmp(arg, "flex") == 0
				|| strcasecmp(arg, "cmd") == 0)
				{
					output_format = FMT_FLEX_CMD;
					if(current_cpu == CPU_UNSET)
						current_cpu = CPU_M68;
				}
				else if(strcasecmp(arg, "debug") == 0)
				{
					output_format = FMT_DEBUG;
				}
				else
				{
					fprintf(stderr, "Error: Unknown format `%s'\n", arg);
					exit(1);
				}
			}
			else
			{
				fprintf(stderr, "Unknown flag: `%s'\n", argv[argi]);
			}
		}
		else
		{
			if(input_filename != NULL)
			{
				fprintf(stderr, "Multiple input files unimplemented, ignoring `%s'\n", argv[argi]);
				continue;
			}
			input_filename = argv[argi];
		}
	}
	if(input_filename == NULL)
	{
		fprintf(stderr, "No input files provided, reading from standard input\n");
	}
	else
	{
		stdin = freopen(input_filename, "r", stdin);
	}
	int result;
	if(current_cpu == CPU_M68)
	{
		result = parse();
	}
	else
	{
		fprintf(stderr, "Unspecified architecture\n");
		return 1;
	}
	if(result != 0)
		return result;

	for(instruction_t * instr = instruction_stream; instr != NULL; instr = instr->next)
	{
		if(instr->mnem == DIR_DEFINE && instr->opd[0]->parameter->s != NULL)
			define(instr->opd[0]->parameter->s, instr);
	}

	fclose(stdin);

	process_state = PROCESS_PRERUN;
	process_file();

	process_state = PROCESS_CALCULATE;
	bool changed = true;
	while(changed)
	{
		changed = process_file();
	}

	if(output_filename == NULL && output_format != FMT_DEBUG)
	{
		if(input_filename == NULL)
		{
			output_filename = "a.out";
		}
		else
		{
			size_t offset;
			char * dot = strrchr(input_filename, '.');
			if(dot != NULL)
			{
				/* check if it is part of the path instead of the file name */
				char * slash = strchr(dot, '/');
				if(slash != NULL)
					dot = NULL;
			}
			if(dot == NULL)
				offset = strlen(input_filename);
			else
				offset = dot - input_filename;
			output_filename = malloc(offset + 5);
			memcpy(output_filename, input_filename, offset);
			strcpy(output_filename + offset, ".out");
		}
	}

	if(output_format != FMT_DEBUG)
		output_file = fopen(output_filename, "wb");

	process_state = PROCESS_GENERATE;
	process_file();

	finish();

	return 0;
}

