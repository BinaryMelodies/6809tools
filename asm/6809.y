
%code requires
{
#include "6809asm.h"
#define yylval m68_lval
}

%{
#include <assert.h>
#include <stdio.h>
#include "asm.h"
extern int m68_lex(void);
#define yylex m68_lex
void m68_error(const char * s);

void yyerror(const char * s);

extern int reg_stack_flag[];

#define MAKE_IDX(reg, mode) ((((reg) - REG_X) << 5) | (mode))
%}

%define api.prefix {m68_}

%union
{
	int i;
	char * s;

	operand_t * o;
	expression_t * x;
}

%token <i> TOK_CHARACTER
%token <i> TOK_DIR
%token <s> TOK_IDENTIFIER
%token <i> TOK_INTEGER
%token <s> TOK_STRING

%token DEL_NE "!="
%token DEL_EQ "=="
%token DEL_LE "<="
%token DEL_GE ">="
%token DEL_SHL "<<"
%token DEL_SHR ">>"

%token KWD_ALIGN
%token <i> KWD_DATA
%token KWD_ENTRY
%token KWD_ORG

%token <i> TOK_AREG TOK_BREG TOK_DREG
%token <i> TOK_IXREG /* u s x y */
%token KWD_MODE6800 KWD_MODE6809
%token <i> MNEM0 MNEM1 MNEM1T MNEM1I MNEM1R MNEM1X MNEM2 MNEML
%token <i> TOK_PCREL /* pcr */
%token <i> TOK_PCREG /* pc */
%token <i> TOK_REG /* dp cc */

%left "!=" "=="
%left '<' '>' "<=" ">="
%left '|'
%left '^'
%left '&'
%left '+' '-'
%left '*' '/' '%' "<<" ">>"
%right '~' PREFIX

%type <i> register
%type <i> register_list
%type <i> data_directive

%type <x> expression expression_noparen

%type <o> address_a address_b address1 address2 indexed_operand operand m6800_operand

%%

file
	: file_prefix
	| file m6800_section
	| file m6809_section
	;

file_prefix
	:
	| file_prefix directive
	;

m6800_section
	: KWD_MODE6800 '\n'
	| m6800_section directive
	| m6800_section m6800_instruction '\n'
	;

m6809_section
	: KWD_MODE6809 '\n'
	| m6809_section directive
	| m6809_section m6809_instruction '\n'
	;

directive
	: '\n'
	| TOK_IDENTIFIER ':'
		{
			instruction_stream_label($1);
		}
	| TOK_IDENTIFIER '=' expression '\n'
		{
			instruction_stream_define($1, $3);
		}
	| KWD_ORG expression '\n'
		{
			instruction_stream_reposition($2);
		}
	| here '=' expression '\n'
		{
			instruction_stream_reposition($3);
		}
	| KWD_ENTRY expression '\n'
		{
			instruction_stream_set_entry($2);
		}
	;

data_directive
	: KWD_DATA expression
		{
			instruction_stream_data($1, $2);
			$$ = $1;
		}
	| KWD_DATA TOK_STRING
		{
			instruction_stream_string($1, $2);
			$$ = $1;
		}
	| data_directive ',' expression
		{
			instruction_stream_data($1, $3);
			$$ = $1;
		}
	| data_directive ',' TOK_STRING
		{
			instruction_stream_string($1, $3);
			$$ = $1;
		}
	;

m6800_instruction
	: data_directive
	| MNEM0
		{
			m68_instruction_create1($1, operand_make(OPD_NONE, IGNORE, NULL))->m6809 = false;
		}
	| MNEM1 m6800_operand
		{
			m68_instruction_create1($1, $2)->m6809 = false;
		}
	| MNEM1 '#' expression
		{
			m68_instruction_create1($1, operand_make(OPD_IMMB, IGNORE, $3))->m6809 = false;
		}
	| MNEM1R expression
		{
			m68_instruction_create1($1, operand_make(OPD_RELB, IGNORE, $2))->m6809 = false;
		}
	| MNEM1T m6800_operand
		{
			m68_instruction_create1($1, $2)->m6809 = false;
		}
	;

m6809_instruction
	: data_directive
	| MNEM0
		{
			m68_instruction_create1($1, operand_make(OPD_NONE, IGNORE, NULL))->m6809 = true;
		}
	| MNEM1 operand
		{
			m68_instruction_create1($1, $2)->m6809 = true;
		}
	| MNEM1 '#' expression
		{
			m68_instruction_create1($1, operand_make(OPD_IMMB, IGNORE, $3))->m6809 = true;
		}
	| MNEM1R expression
		{
			m68_instruction_create1($1, operand_make(OPD_RELB, IGNORE, $2))->m6809 = true;
		}
	| MNEM1T operand
		{
			m68_instruction_create1($1, $2)->m6809 = true;
		}
	| MNEM1I '#' expression
		{
			m68_instruction_create1($1, operand_make(OPD_IMMB, IGNORE, $3))->m6809 = true;
		}
	| MNEM1X indexed_operand
		{
			m68_instruction_create1($1, $2)->m6809 = true;
		}
	| MNEM2 register ',' register
		{
			m68_instruction_create1($1, operand_make(OPD_REG2, ($2 << 4) | $4, NULL))->m6809 = true;
		}
	| MNEML register_list
		{
			m68_instruction_create1($1, operand_make(OPD_REGLIST, $2, NULL))->m6809 = true;
		}
	;

m6800_operand
	: expression
		{
			$$ = operand_make(OPD_DIR, IGNORE, $1);
		}
	| TOK_IXREG
		{
			$$ = operand_make(OPD_IND, IGNORE, NULL);
		}
	| ',' TOK_IXREG
		{
			$$ = operand_make(OPD_IND, IGNORE, NULL);
		}
	| expression ',' TOK_IXREG
		{
			$$ = operand_make(OPD_IND, IGNORE, $1);
		}
	;

operand
	: '<' expression
		{
			$$ = operand_make(OPD_DIR, IGNORE, $2);
		}
	| expression
		{
			$$ = operand_make(OPD_EXT, IGNORE, $1);
		}
	| address1
		{
			$$ = $1;
			$$->type = OPD_IND;
		}
	| '[' address2 ']'
		{
			$$ = $2;
			$$->type = OPD_IND;
			$$->idx |= 0x10;
		}
	;

indexed_operand
	: address1
		{
			$$ = $1;
			$$->type = OPD_IND;
		}
	| '[' address2 ']'
		{
			$$ = $2;
			$$->type = OPD_IND;
			$$->idx |= 0x10;
		}
	;

address1
	: address_a
	| address_b
	;

address2
	: expression
		{
			$$ = operand_make(IGNORE, 0x9F, $1);
		}
	| address_a
	;

address_b
	: ',' TOK_IXREG '+'
		{
			$$ = operand_make(IGNORE, MAKE_IDX($2, 0x00), NULL);
		}
	| ',' '-' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x02), NULL);
		}
	| TOK_IXREG '+'
		{
			$$ = operand_make(IGNORE, MAKE_IDX($1, 0x00), NULL);
		}
	| '-' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($2, 0x02), NULL);
		}
	;

address_a
	: TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($1, 0x04), NULL);
		}
	| ',' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($2, 0x04), NULL);
		}
	| expression ',' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x04), $1);
		}
	| TOK_AREG ',' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x06), NULL);
		}
	| TOK_BREG ',' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x05), NULL);
		}
	| TOK_DREG ',' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x0B), NULL);
		}
	| ',' TOK_IXREG '+' '+'
		{
			$$ = operand_make(IGNORE, MAKE_IDX($2, 0x01), NULL);
		}
	| ',' '-' '-' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($4, 0x03), NULL);
		}
	| TOK_IXREG '+' '+'
		{
			$$ = operand_make(IGNORE, MAKE_IDX($1, 0x01), NULL);
		}
	| '-' '-' TOK_IXREG
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x03), NULL);
		}
	| expression ',' TOK_PCREL
		{
			$$ = operand_make(IGNORE, MAKE_IDX($3, 0x0C), $1);
		}
	;

register
	: TOK_AREG
	| TOK_BREG
	| TOK_DREG
	| TOK_IXREG
	| TOK_PCREG
	| TOK_REG
	;

register_list
	: register
		{
			$$ = reg_stack_flag[$1];
		}
	| register_list ',' register
		{
			$$ = $1 | reg_stack_flag[$3];
		}
	;

here
	: '*'
	| '.'
	;


expression_noparen
	: TOK_IDENTIFIER
		{
			$$ = expression_identifier($1);
		}
	| TOK_INTEGER
		{
			$$ = expression_integer($1);
		}
	| TOK_CHARACTER
		{
			$$ = expression_integer($1);
		}
	| here
		{
			$$ = expression_make(EXP_HERE);
		}
	| KWD_ALIGN '(' expression ',' expression ')'
		{
			$$ = expression_binary(EXP_ALIGN, $3, $5);
		}
	| '+' expression %prec PREFIX
		{
			$$ = expression_unary(EXP_PLUS, $2);
		}
	| '-' expression %prec PREFIX
		{
			$$ = expression_unary(EXP_MINUS, $2);
		}
	| '~' expression
		{
			$$ = expression_unary('~', $2);
		}
	| expression "<<" expression
		{
			$$ = expression_binary(EXP_SHL, $1, $3);
		}
	| expression ">>" expression
		{
			$$ = expression_binary(EXP_SHR, $1, $3);
		}
	| expression '*' expression
		{
			$$ = expression_binary('*', $1, $3);
		}
	| expression '/' expression
		{
			$$ = expression_binary('/', $1, $3);
		}
	| expression '%' expression
		{
			$$ = expression_binary('%', $1, $3);
		}
	| expression '+' expression
		{
			$$ = expression_binary('+', $1, $3);
		}
	| expression '-' expression
		{
			$$ = expression_binary('-', $1, $3);
		}
	| expression '&' expression
		{
			$$ = expression_binary('&', $1, $3);
		}
	| expression '^' expression
		{
			$$ = expression_binary('^', $1, $3);
		}
	| expression '|' expression
		{
			$$ = expression_binary('|', $1, $3);
		}
	| expression '<' expression
		{
			$$ = expression_binary('<', $1, $3);
		}
	| expression '>' expression
		{
			$$ = expression_binary('>', $1, $3);
		}
	| expression "==" expression
		{
			$$ = expression_binary(EXP_EQ, $1, $3);
		}
	| expression "!=" expression
		{
			$$ = expression_binary(EXP_NE, $1, $3);
		}
	| expression "<=" expression
		{
			$$ = expression_binary(EXP_LE, $1, $3);
		}
	| expression ">=" expression
		{
			$$ = expression_binary(EXP_GE, $1, $3);
		}
	;

expression
	: expression_noparen
	| '(' expression ')'
		{
			$$ = expression_unary(EXP_PAREN, $2);
		}
	;

%%

void m68_error(const char * s)
{
	fprintf(stderr, "Error: %s\n", s);
}

