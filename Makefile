
CFILES=asm/asm.c out/6809.yy.c out/6809.tab.c out/6809asm.c
CFLAGS=-Wall -g -I lib -I out -I asm

all: bin/6809asm bin/6809emu tests

clean:
	rm -fr bin out

distclean: clean
	rm -fr *~ */*~

.PHONY: all tests clean distclean

bin/6809asm: $(CFILES) asm/asm.h out/6809asm.h Makefile
	mkdir -p bin
	gcc -o $@ $(CFILES) $(CFLAGS)

tests: bin/test.o68 bin/test.o69

bin/6809emu: emu/6809emu.c bin/lib6809.so
	mkdir -p bin
	gcc -o $@ emu/6809emu.c $(CFLAGS) -L bin -l6809

bin/lib6809.so: out/6809lib.c
	mkdir -p bin
	gcc -fPIC -shared -o $@ $^ $(CFLAGS)

bin/test.o68: test/test.s68 bin/6809asm
	mkdir -p bin
	bin/6809asm -f cmd $< -o $@

bin/test.o69: test/test.s69 bin/6809asm
	mkdir -p bin
	bin/6809asm -f cmd $< -o $@

out/6809.def: lib/6809.py lib/6809.dat
	mkdir -p out
	python3 $< -o $@ lib/6809.dat

out/6809.lex: weave.py out/6809.def asm/6809.lex.t
	mkdir -p out
	python3 weave.py -d out/6809.def asm/6809.lex.t -o $@

out/6809lib.c: weave.py out/6809.def lib/6809lib.c.t
	mkdir -p out
	python3 weave.py -d out/6809.def lib/6809lib.c.t -o $@

out/6809asm.c: weave.py out/6809.def asm/6809asm.c.t
	mkdir -p out
	python3 weave.py -d out/6809.def asm/6809asm.c.t -o $@

out/6809asm.h: weave.py out/6809.def asm/6809asm.h.t
	mkdir -p out
	python3 weave.py -d out/6809.def asm/6809asm.h.t -o $@

out/%.yy.c: out/%.lex
	mkdir -p out
	flex -o $@ $^

out/%.tab.c: asm/%.y
	mkdir -p out
	bison -d $^ -o $@

.SUFFIXES:

