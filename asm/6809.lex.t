
%{
#include "6809.tab.h"
%}

%option noyywrap
%option noinput
%option nounput
%option prefix="m68_"

%s M6800 M6809
%%

[ \t]+	;
;.*	;

".6800"	{ BEGIN(M6800); return KWD_MODE6800; }
".6809"	{ BEGIN(M6809); return KWD_MODE6809; }

".org"	{ return KWD_ORG; }
".align"	{ return KWD_ALIGN; }
".entry"	{ return KWD_ENTRY; }

".byte"	{ yylval.i = 1; return KWD_DATA; }
".word8"	{ yylval.i = 1; return KWD_DATA; }
".word8le"	{ yylval.i = 1; return KWD_DATA; }
".word8be"	{ yylval.i = 1; return KWD_DATA; }
".word16le"	{ yylval.i = 2 | FLAG_LITTLE_ENDIAN; return KWD_DATA; }
".word16be"	{ yylval.i = 2 | FLAG_BIG_ENDIAN; return KWD_DATA; }

".word"	{ yylval.i = 2 | FLAG_BIG_ENDIAN; return KWD_DATA; }
".wordle"	{ yylval.i = 2 | FLAG_LITTLE_ENDIAN; return KWD_DATA; }
".wordbe"	{ yylval.i = 2 | FLAG_BIG_ENDIAN; return KWD_DATA; }
".word16"	{ yylval.i = 2 | FLAG_BIG_ENDIAN; return KWD_DATA; }

<M6809>"a"	{ yylval.i = REG_A; return TOK_AREG; }
<M6809>"b"	{ yylval.i = REG_B; return TOK_BREG; }
<M6809>"d"	{ yylval.i = REG_D; return TOK_DREG; }
<M6809>"u"	{ yylval.i = REG_U; return TOK_IXREG; }
<M6809>"s"	{ yylval.i = REG_S; return TOK_IXREG; }
"x"	{ yylval.i = REG_X; return TOK_IXREG; }
<M6809>"y"	{ yylval.i = REG_Y; return TOK_IXREG; }
<M6809>"dp"	{ yylval.i = REG_DP; return TOK_REG; }
<M6809>"cc"	{ yylval.i = REG_CC; return TOK_REG; }
<M6809>"pcr"	{ yylval.i = REG_PC; return TOK_PCREL; }
<M6809>"pc"	{ yylval.i = REG_PC; return TOK_PCREG; }

@INCLUDE_MNEMONICS_LEX

"."	{ return yytext[0]; }

[.A-Za-z_][.A-Za-z_0-9]*	{ yylval.s = strdup(yytext); return TOK_IDENTIFIER; }
0|[1-9][0-9]*	{ yylval.i = strtol(yytext, NULL, 10); return TOK_INTEGER; }
$[0-9A-Fa-f]+	{ yylval.i = strtol(yytext + 1, NULL, 16); return TOK_INTEGER; }
0[Xx][0-9A-Fa-f]+	{ yylval.i = strtol(yytext + 2, NULL, 16); return TOK_INTEGER; }
&[0-9A-Fa-f]+	{ yylval.i = strtol(yytext + 1, NULL, 8); return TOK_INTEGER; }
0[Oo][0-7]+	{ yylval.i = strtol(yytext + 2, NULL, 8); return TOK_INTEGER; }
%[0-9A-Fa-f]+	{ yylval.i = strtol(yytext + 1, NULL, 2); return TOK_INTEGER; }
0[Bb][01]+	{ yylval.i = strtol(yytext + 2, NULL, 2); return TOK_INTEGER; }

\"[^"\n]*\"	{ yytext[strlen(yytext) - 1] = '\0'; yylval.s = strdup(yytext + 1); return TOK_STRING; }
\'[^'\n]*\'	{ yytext[strlen(yytext) - 1] = '\0'; yylval.s = strdup(yytext + 1); return TOK_STRING; }

"<<"	{ return DEL_SHL; }
">>"	{ return DEL_SHR; }

.|\n	{ return yytext[0]; }

%%

