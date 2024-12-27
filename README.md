# A Motorola 6800/6809 assembler and emulator

This repository provides the sources for a very simple Motorola [6800](https://en.wikipedia.org/wiki/Motorola_6800)/[6809](https://en.wikipedia.org/wiki/Motorola_6809) assembler and emulator.
The assembler uses a syntax very similar to that of the GNU assembler.
The emulator can almost fully emulate either a 6800 and a 6809 (except for interrupts), and a very limited version of [FLEX](https://en.wikipedia.org/wiki/FLEX_(operating_system)).
The CPU emulator is also compiled as a stand alone shared library.

# Compilation

On Linux, the entire project, including the assembler, CPU emulator library, emulator and test programs can be compiled by invoking `make`.
Compilation requires a C compiler, a Python interpreter, as well as the [Flex](https://github.com/westes/flex) and [GNU Bison](https://www.gnu.org/software/bison/) tools and make.
No other platforms have been tested.

# Invocation

The assembler can be invoked by `bin/6809asm`.
It recognizes three flags: `-m` for target type (only 6800/6809 supported), `-o` for the output file and `-f` for the file format.
Target type has to be included: `-m 6800`.
The actual target has to be included in the source file as a directive, `.6800` or `.6809`.
The currently supported file formats are flat binaries or FLEX `.cmd` binaries.

The emulator can be invoked by `bin/6809emu`.
By default, it emulates a 6809 CPU with FLEX.
The flag `-m 6800` can be used to select a 6800 CPU.
Note that the compiled shared library `bin/lib6809.so` has to be in the shared library path.

# Project structure

Many files in the project are provided as templates that have to be processed via `weave.py`.

The `asm/` directory contains the sources for the assembler.
The assembler has been a part of a larger project attempt, and so it is divided into a generic and a platform specific part, with some references to other architectures left in.

The `lib/` directory contains the sources for the CPU emulator library.

The `emu/` directory contains the source for the actual emulator.

The `test/` directory contains test files for the assembler.

The intermediate outputs of the `weave.py` script, as well as those of Flex and GNU Bison are placed under the `out/` folder.
The final binaries will appear under `bin/`.

# Disclaimer

The state of this tool pack is in alpha stage, it was developed purely for personal use.
It has been released to the public in the hopes it can be useful for others.
The correctness of the emulation has not been verified and comes with no warranty.

For documentation on the tools, please look at the sources, the example assembly files or Makefile.
To use the assembler, familiarity with the Motorola 6800 and/or 6809 architectures is required, for which references have to be obtained from elsewhere.

