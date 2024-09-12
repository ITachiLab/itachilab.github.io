Put arbitrary data into binary
==============================

When developing stuff for embedded platforms it might happen that there's a need to include some arbitrary chunk of data into the final binary. When size of the data is not big, and it's not expected to be modified frequently, it can be kept as a constant array of bytes, words, or whatever. Depending on a target platform and a toolchain, linker puts constants into the flash memory out of the box, or it might require additional steps. For example, on AVR platform one can use `PROGMEM`_ macro to mark objects which should be placed in the flash memory. On `RP2040`_ (ARM) it should be enough to add ``const`` modifier because ``.rodata`` section is part of a flash region.

It starts to be more complicated when size of the data is significant, let's say it's 2 MB. Why would anyone keep data that big on an embedded platform? Reasons are different, this can be some image to display, a WAV file to play, or a configuration file. No matter the reason, it's going to be an horror to keep and maintain an array of 2 million elements. And what if the data changes? I can't imagine recreating the array, even with some help of Python scripts. The ideal solution would be including these files automatically when the binary is built. Good news - it's possible!

Know the platform
-----------------

Unfortunately, there's no universal solution, as I mentioned in the introduction - different platforms might require different approaches. What's universal though is the goal: the data must be in the flash memory, and it must be accessible from code. There's no magic here, unless some fancy frameworks are in use, and everything usually starts from reading a linker script used for assembling the final binary. For this article I'm using RP2040, known better as: *Raspberry Pi Pico*.

Analyze the linker script
+++++++++++++++++++++++++

A linker script used by default when building binaries for RP2040 is located at: ``{SDK_ROOT}/src/rp2_common/pico_standard_link/memmap_default.ld``. The most interesting sections are those put to the **FLASH** region and having input sections named like they are meant to keep read-only data. For RP2040 I've got something like this::

    .rodata : {
        *(EXCLUDE_FILE(*libgcc.a: *libc.a:*lib_a-mem*.o *libm.a:) .rodata*)
        . = ALIGN(4);
        *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.flashdata*)))
        . = ALIGN(4);
    } > FLASH

There are two important things happening here: the first is obviously presence of ``.rodata`` input section which is dedicated to constant data, and the second is an input section named ``.flashdata*``. This is not a one of the well-known sections, this is something added by Raspberry guys, they foresaw what people would want to do. Generally speaking, this output section will consist of all ``.rodata`` sections from all object files (with a few minor exceptions), followed by sections which name starts with ``.flashdata`` and come from any object file.

.. highlight:: c

To start with, I created a simple, global ``int`` in my code::

    int foobar = 10;

.. highlight:: text

I used it somewhere to prevent it from being optimized away, then I compiled the code and used ``objdump`` to see where it's been placed::

    $ arm-none-eabi-objdump -t output.elf | grep foobar
    20000460 g     O .data  00000004 foobar

What can be read from the output is that the ``foobar`` symbol lays in the ``.data`` section, what usually means it's going to be accessible from RAM, but programmed into a flash memory. I said "usually" because it doesn't have to be like that. The address of the symbol, visible in the first column, points to a RAM memory on RP2040 platform.

.. note::
   This is the reason why it's wise to avoid having global initialized variables in embedded systems - they need a space in RAM for the whole time of running a program, and also take space in a flash memory, becasue the initial value won't magically appear out of nowhere. Of course it's not a sin to use them when it's necessary.

.. highlight:: c

The goal is to put the data into a flash memory, so let's compare two methods of doing this. I created the following global symbols in my code::

    const int foobar_const = 10;
    int foobar_section __attribute__ ((section (".flashdata"))) = 20;

.. highlight:: text

And object dump again::

    $ arm-none-eabi-objdump -t output.elf | grep foobar
    1000d014 g     O .rodata        00000004 foobar_section

``foobar_section`` now lives in the ``.flashdata`` section, and the address is a part of a flash region. But where is ``foobar_const``? I expected it to appear under a similar address since I made it a ``const``, but compiler decided to embed it in expressions instead, which is actually a good decision. Just for the presentation purposes I made it to don't do that, so the dump now looks like below::

    $ arm-none-eabi-objdump -t output.elf | grep foobar
    10007c9c g     O .rodata        00000004 foobar_const
    1000d01c g     O .rodata        00000004 foobar_section

Although both methods of storing data in a flash work correctly, using ``const`` for such purpose might give results not entirely expected, so let's stick to the other method, and give a target section manually. However, this still doesn't solve the problem of storing and supplying large chunks of data for compilation. For this, a little help of assembler is needed.

Include with .incbin
--------------------

.. highlight:: asm

ARM assembler (and other assemblers usually) supports a neat directive called: `.incbin <incbin_>`_. The purpose of this directive is of course to include a binary data from a file. Now, in order to use it, an assembler file must be created and added as a source file to the project. The content of the file should be::

    .section    .flashdata
    .balign     4
    .global     data_file_1
    .global     data_file_1_size
    data_file_1:
    .incbin     "file1"
    .set        data_file_1_size, . - data_file_1

This small piece of an assembly includes in the current position whatever is in the **file1** file. The "current position" is in this case somewhere in the ``.flashdata`` section, aligned to 4 bytes boundary. The actual placement is unknown until the file is compiled and linked. Thanks to having two global symbols - one with an address of the data, and second with its size - the data can be accessed later from a C code. Although having a separate symbol for the size is optional, it comes very handy.

.. tip::
   Compiler will look for files given to ``.incbin`` directive in the include directories, i.e. directories supplied to compiler with the ``-I`` option. When using CMake, the directories can be added with ``target_include_directories`` function.

.. highlight:: c

In order to use foreign symbols in a C code, they must be defined like this::

    extern const char data_file_1[];
    extern const char data_file_1_size[];

.. highlight:: text

Type of the symbols doesn't matter because they are only placeholders for the symbol values. The following object dump should help understand this::

    1000d044 g       .rodata        00000000 data_file_1
    0000002d g       *ABS*  00000000 data_file_1_size

The first column is a "symbol value", that means this is the value to which the symbol will resolve when it's used. For ``data_file_1`` the value is an address in a memory, but for ``data_file_1_size`` the value is just a raw number equal to the size of the data.

.. highlight:: c

On RP2040 I can now print the content to the console::

    printf("%.*s", (int) data_file_1_size, data_file_1);

In my file I had some text content. It isn't null-terminated by default, so I had to supply the size manually.

Automate with .macro
++++++++++++++++++++

.. highlight:: text

Everything looks okay, until there's a need to include 10, or 20 files. Quick copy-paste of the assembly listing I gave above would solve the problem, but this looks bad. What to do now? Of course - another directive! ::

    .macro      incfile file:req, name:req
    .section    .flashdata
    .balign     4
    .global     \name
    .global     \name\()_size
    \name:
    .incbin     "\file"
    .set        \name\()_size, . - \name
    .endm

This is the same code as before but wrapped in a macro. The macro takes two arguments: a file name, and a symbol name. Now, instead of ugly duplications, multiple files can be included like below::


    incfile file1,data_file_1
    incfile file2,data_file_2

The symbols can be referenced later in a C code as before: ``data_file_1``, ``data_file_1_size``, ``data_file_2``, and ``data_file_2_size``.

----

.. target-notes::

.. _`PROGMEM`: https://www.nongnu.org/avr-libc/user-manual/group__avr__pgmspace.html#ga75acaba9e781937468d0911423bc0c35
.. _`RP2040`: https://www.raspberrypi.com/products/rp2040/
.. _`incbin`: https://sourceware.org/binutils/docs/as/Incbin.html
