
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "6809lib.h"

#define VERSION "0.9"

void m6809_debug(FILE * file, m6809_t * cpu)
{
	if(cpu->emu6800)
	{
		fprintf(file, "A = %02X, B = %02X, X = %04X, S = %04X, PC = %04X, CC = %02X\n",
			cpu->d >> 8, cpu->d & 0xFF, cpu->x, cpu->s, cpu->pc, cpu->cc);
	}
	else
	{
		fprintf(file, "D = %04X, X = %04X, Y = %04X, U = %04X, S = %04X, PC = %04X, DP = %02X, CC = %02X\n",
			cpu->d, cpu->x, cpu->y, cpu->u, cpu->s, cpu->pc, cpu->dp, cpu->cc);
	}
}

m6809_t CPU;

unsigned load_flat(m6809_t * cpu, FILE * file)
{
	for(int i = 0x100, c = fgetc(file); c != -1; i++, c = fgetc(file))
	{
		m6809_write_byte(i, c);
	}
	return 0x100;
}

unsigned load_cmd(m6809_t * cpu, FILE * file)
{
	unsigned start = 0;
	int c;
	while((c = fgetc(file)) != -1)
	{
		switch(c)
		{
		case 0x02:
			{
				unsigned address, length;
				address = fgetc(file) << 8;
				address |= fgetc(file) & 0xFF;
				length = fgetc(file) & 0xFF;
				for(int i = 0; i < length; i++)
					m6809_write_byte(address++, fgetc(file));
			}
			break;
		case 0x16:
			start = fgetc(file) << 8;
			start |= fgetc(file) & 0xFF;
			break;
		}
	}
	return start;
}

#define FLEX_ENTRY (CPU.emu6800 ? 0xAD00 : 0xCD00)
#define FLEX_WARMS 0x0003
#define FLEX_PSTRNG 0x001E
#define FLEX_PUTCHR 0x0018
#define FLEX_GETCHR 0x0015

void usage(char * argv0)
{
	fprintf(stderr,
		"Motorola 6800/6809 emulator version " VERSION "\n"
		"Usage: %s [-d] [-c (6800|6809)] [-h] <binary name>\n"
		"\t-d\tenable debugging\n"
		"\t-c 6800\temulate 6800\n"
		"\t-c 6809\temulate 6809 (default)\n"
		"\t-h\tprint this text and quit\n"
		"\t<binary name>\tstored in flat file format or FLEX .cmd format\n",
			argv0);
}

int main(int argc, char * argv[])
{
	char * filename = NULL;
	FILE * file;
	int argi;
	for(argi = 1; argi < argc; argi++)
	{
		if(argv[argi][0] == '-')
		{
			if(argv[argi][1] == 'c')
			{
				char * arg = argv[argi][2] ? &argv[argi][2] : argv[++argi];
				if(strcmp(arg, "6800") == 0)
				{
					CPU.emu6800 = true;
				}
				else if(strcmp(arg, "6809") == 0)
				{
					CPU.emu6800 = false;
				}
				else
				{
					fprintf(stderr, "Unknown CPU type: %s\n", arg);
					usage(argv[0]);
					exit(1);
				}
			}
			else if(argv[argi][1] == 'd')
			{
				CPU.debug = true;
			}
			else if(argv[argi][1] == 'h')
			{
				usage(argv[0]);
				exit(0);
			}
			else
			{
				fprintf(stderr, "Unknown flag %s\n", argv[argi]);
				usage(argv[0]);
				exit(1);
			}
		}
		else
		{
			filename = argv[argi];
			break;
		}
	}
	if(filename == NULL)
	{
		fprintf(stderr, "Expected file name\n");
		exit(1);
	}
	file = fopen(filename, "rb");
	if(file == NULL)
	{
		fprintf(stderr, "Unable to open file %s\n", filename);
		exit(1);
	}
	if(fgetc(file) == 0x02)
	{
		fseek(file, 0L, SEEK_SET);
		CPU.pc = load_cmd(&CPU, file);
	}
	else
	{
		fseek(file, 0L, SEEK_SET);
		CPU.pc = load_flat(&CPU, file);
	}
	fclose(file);
	for(;;)
	{
		if(CPU.debug)
		{
			m6809_debug(stderr, &CPU);
			getchar();
		}
		switch(CPU.pc - FLEX_ENTRY)
		{
		case FLEX_WARMS:
			exit(0);
			break;
		case FLEX_PUTCHR:
			putchar(GETA(&CPU));
			CPU.pc = PULLW(s, &CPU);
			break;
		case FLEX_GETCHR:
			SETA(&CPU, getchar());
			CPU.pc = PULLW(s, &CPU);
			break;
		case FLEX_PSTRNG:
			printf("\r\n"); /* this is the first step */
			for(unsigned address = CPU.x, i = 0; i < 0x10000; i++, address = (address + 1) & 0xFFFF)
			{
				int c = m6809_read_byte(address);
				if(c == 0x04)
					break;
				putchar(c);
			}
			CPU.pc = PULLW(s, &CPU);
			break;
		default:
			m6809_step(&CPU);
			break;
		}
	}
}

