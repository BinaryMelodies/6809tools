#ifndef _M6809LIB_H
#define _M6809LIB_H

#include <stdint.h>
#include <stdbool.h>

typedef struct m6809_t
{
	/* CPU registers */
	uint16_t d, x, y, u, s, pc;
	uint8_t dp, cc;
	/* Set to true if emulating a 6800 instead of a 6809 */
	bool emu6800;
	bool debug;
} m6809_t;

#define CC_C 0x01
#define CC_V 0x02
#define CC_Z 0x04
#define CC_N 0x08
#define CC_I 0x10
#define CC_H 0x20
#define CC_F 0x40
#define CC_E 0x80

#define IV_SWI3  0xFFF2
#define IV_SWI2  0xFFF4
#define IV_FIRQ  0xFFF6
#define IV_IRQ   0xFFF8
#define IV_SWI   0xFFFA
#define IV_NMI   0xFFFC
#define IV_RESET 0xFFFE

#define SETA(cpu, a) ((cpu)->d = ((cpu)->d & 0x00FF) | (((a) & 0xFF) << 8))
#define GETA(cpu)    (((cpu)->d) >> 8 & 0xFF)

#define SETB(cpu, b) ((cpu)->d = ((cpu)->d & 0xFF00) | ((b) & 0xFF))
#define GETB(cpu)    ((cpu)->d & 0xFF)

#define GETC(cpu)    ((cpu)->cc & CC_C)

uint8_t m6809_read_byte(uint16_t address);
void m6809_write_byte(uint16_t address, uint8_t value);
uint16_t m6809_read_word(uint16_t address);
void m6809_write_word(uint16_t address, uint16_t value);

#define FETCH(cpu) (m6809_read_byte((cpu)->pc++))
#define FETCHW(cpu) ((cpu)->pc += 2, m6809_read_word((cpu)->pc - 2))
#define PUSH(S, cpu, v) (m6809_write_byte((cpu)->emu6800 ? (cpu)->S-- : --(cpu)->S, (v)))
#define PUSHW(S, cpu, v) ((cpu)->S -= 2, m6809_write_word((cpu)->S + ((cpu)->emu6800 ? 1 : 0), (v)))
#define PULL(S, cpu) (m6809_read_byte((cpu)->emu6800 ? ++(cpu)->S : (cpu)->S++))
#define PULLW(S, cpu) ((cpu)->S += 2, m6809_read_word((cpu)->S - ((cpu)->emu6800 ? 1 : 2)))

void m6809_step(m6809_t * cpu);

#endif /* _M6809LIB_H */
