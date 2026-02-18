Linker Script from scratch
==========================

In this article I'm going to show how to create a simple yet functional linker script. I'm going to target an STM32 microcontroller, because embedded targets are usually the reason why someone would like to create a linker script. The linker script created in this article can't compete with the linker script provided by the manufacturer, and it's not a purpose of this article to create something better. The goal is to understand how these linker scripts are created and to see that it isn't impossible to create one on your own.

This article describes three main points:

- how to write a simple linker script from scratch,
- how to do this for STM32 microcontrollers,
- how to avoid using vendor's files (headers, codes etc.)

.. note::
    This is something new for me as well. I'm always using scripts provided by vendors, but I decided to do this by myself, partially because I like raping my brain, but mostly to learn something new. I really recommend going through the `Mastering the GNU linker script`_ article first.

I decided to focus on linker scripts for microcontrollers, because they require good understanding of the target platform, and gives an opportunity to decide about everything (mostly).

Prepare tools
-------------

Two things are needed to start: ARM toolchain, and a text editor. The newest ARM toolchain can be downloaded directly from `ARM`_.  On Linux, the toolchain can be just extracted anywhere and prepended to the ``PATH`` environment variable::

    export PATH=/your/toolchain/bin:$PATH

Prepare knowledge
-----------------

It's ultimately important to know the memory layout of the target devices. It's impossible to write a linker script without knowing where to put the code, where to put data etc. The memory layout differs between architectures and devices, so the only way to know "what and where" is to grab a datasheet, and find the information in it. For *STM32F103RBT6* it can be found in its `reference manual <STM32F103RBT6_>`_ on page **53** (for SRAM) and page **54** (for flash).

:SRAM: 0x20000000
:Flash: 0x08000000

This essentially means that the code must be available at address ``0x08000000``, and all variable data at ``0x20000000``. It will be explained later in more detail.

The next important thing is to know how a microcontroller boots. For most of the time the developer is responsible for setting up the stack pointer at device boot time and this is done differently for different architectures. The recipe is straightforward: find how to set up stack pointer, and set it up to the top of the SRAM memory. It's logical, the stack always grows downwards so it has to have space to grow.

For the STM32 used for this article, this information can be found on page **61** in the `reference manual <STM32F103RBT6_>`_.

    After this startup delay has elapsed, the CPU fetches the top-of-stack value from address ``0x00000000``, then starts code execution from the boot memory starting from ``0x00000004``.

Excellent, more useful things to write down.

:Stack initializer: 0x00000000
:Entry point: 0x00000004

There's also one more important thing to know about STM32, and this is explained on the page **61** too. When the CPU reads from address ``0x00000000`` and further, it actually might access different memories, depending on a selected boot mode. This is called "memory mapping". By default, STM32 boots from flash, so it maps memory region ``0x08000000`` to ``0x00000000``; the flash memory is now accessible both from its original address and ``0x00000000``. This allows CPU to start reading instructions directly from flash.

Having the above information in mind, and assuming the code will be put into the flash memory, the final addresses are:

:Stack initializer: 0x08000000
:Entry point: 0x08000004

.. caution::
    The entry point address **is not** where execution will start. It should contain the address where CPU should jump to start the execution. In other words, dword from ``0x00000000`` will be loaded to SP register, and dword from ``0x00000004`` will be loaded to PC register.

Stupidly Simple Linker Script (SSLS)
------------------------------------

As promised on the beginning, the first goal is to write ANYTHING that works. So let's do this! The simplest linker script can consist of a single block called *SECTIONS*. This block contains all output sections that will written to the binary file. These sections are usually:

:``.text``: The code.
:``.data``: Initialized data (global and static variables).
:``.bss``: Uninitialized data (global and static variables).

For SSLS only the ``.text`` section is important. No data, no variables, just pure code. Without more talking, let's create a file called ``script.ld`` and put something like this to it::

    SECTIONS
    {
        .text : { *(.text) }
    }

The above script tells linker to:

1. Create a ``.text`` section (the leftmost expression).
2. Take all ``.text`` sections from all object files (the expression in curly braces).
3. Put them to the section created in step 1.

That's pretty simple, isn't it? But there's something missing here, even a few somethings. The code section is defined, that's cool, but it's not specified where it should be placed. In the current form, the code will be placed at address ``0x00000000``, but it should be loaded at address ``0x08000000``, according to the previous findings. Let's fix that. ::

    SECTIONS
    {
        . = 0x08000000;
        .text : { *(.text) }
    }

The dot symbol in linker scripts is a location counter. It starts from ``0x00000000`` and can be modified either directly, as in the example above, or indirectly by adding sections, constants etc. The location counter value, when read after the output section ``.text``, would be ``0x08000000`` plus the size of the ``.txt`` section. If address of an output section is not set explicitly (described later), the address is set from the current value of the location counter.

The code is at valid location now, but MCU needs to know about that. As mentioned in the `Prepare knowledge`_ section, MCU reads first 4 bytes to know the top of the stack, and another 4 bytes to know where to begin the execution, and the execution usually begins with the ``main`` function. ::

    ENTRY(main);

    SECTIONS
    {
        . = 0x08000000;
        LONG(0x20005000);
        LONG(main | 1);
        .text : { *(.text) }
    }

The first entry after the location counter instructs linker to place a raw 4-byte value in the output binary. Why this value in particular? SRAM starts at ``0x20000000``, STM32 has 20 kB (``0x5000``) of SRAM memory, ``0x20000000 + 0x5000 = 0x20005000``.

Similarly, an address of the ``main`` function is put to the binary file. But why it's or'ed with ``1``? Here comes the magic of ARM. In ARM architecture, odd function address tells CPU to switch to Thumb mode on branch to this address, as opposed to even addresses, denoting ARM mode. Not all branch instructions cause the mode to switch. ``B`` or ``BL`` instruction branches without switching the mode; ``BX`` branches with additional mode switch accordingly to the last bit of the address; ``BLX`` branches and always switches the mode. More information can be found on the `ARM Branch instruction`_ page.

*STM32F103RBT6* is based on Cortex-M3 which supports only Thumb instructions, this why it is told on the beginning to switch to Thumb mode. This is normally transparent to a developer, compiler either uses ``BL`` instruction to keep the current mode, or changes the calling addresses automatically. The reason why it has to be done manually here is because the linker script is "stupidly simple". This will become clearer after upgrading SSLS to SLS (simple linker script).

I also added another new thing: ``ENTRY(main)``. This tells linker what symbol should be used as the entry point of the program. This prevents ``.text`` section containing the main function from being optimized away by linker.

The SSLS is ready, so the last step is to create a very simply program for Nucleo-F103RB. Let's blink an LED.

.. code-block:: c
    :linenos:

    #include "registers.h"

    void main(void) {
        RCC->APB2ENR |= (1 << RCC_APB2ENR_IOPAEN);
        GPIOA->CRL |= (0b10 << GPIOA_CRL_MODE5);
        GPIOA->CRL &= ~(0b11 << GPIOA_CRL_CNF5);
        GPIOA->BSRR = (1 << 5);

        while (1);
    }

The mysterious ``registers.h`` file is a helper header containing addresses of registers. I've created it from information found in the reference manual. Why not? Since I'm handcrafting a linker script, I can handcraft this too. I simply defined a structure per group of registers, and then defined a pointer to the structure using the base address. Thanks to structures, I don't need to perform manual pointer arithmetic, because it's done automagically when accessing a field of a structure.

.. code-block:: c
    :linenos:

    #ifndef LINKER_TUTORIAL_REGISTERS_H
    #define LINKER_TUTORIAL_REGISTERS_H

    #include <stdint.h>

    typedef struct {
        uint32_t CR;
        uint32_t CFGR;
        uint32_t CIR;
        uint32_t APB2RSTR;
        uint32_t APB1RSTR;
        uint32_t AHBENR;
        uint32_t APB2ENR;
        uint32_t APB1ENR;
        uint32_t BDCR;
        uint32_t CSR;
    } RCC_Reg;

    #define RCC ((RCC_Reg*) 0x40021000)
    #define RCC_APB2ENR_IOPAEN 2

    typedef struct {
        uint32_t CRL;
        uint32_t CRH;
        uint32_t IDR;
        uint32_t ODR;
        uint32_t BSRR;
        uint32_t BRR;
        uint32_t LCKR;
    } GPIOA_Reg;

    #define GPIOA ((GPIOA_Reg*) 0x40010800)
    #define GPIOA_CRL_MODE5 20
    #define GPIOA_CRL_CNF5 22

    #endif //LINKER_TUTORIAL_REGISTERS_H

Since the clock source is not configured, STM32 will use internal 8 MHz RC oscillator, and that's more than sufficient for this simple project. Let's compile and link it::

    $ arm-none-eabi-gcc \
    -mcpu=cortex-m3 \
    -mthumb \
    -Tscript.ld \
    -Wl,--gc-sections \
    -Os \
    main.c

If everything went good, the firmware file will be created as ``a.out``. This file is in ELF format and can't be used directly to flash the microcontroller, instead it must be converted to Intel HEX format. This can be easily done with the following command::

    arm-none-eabi-objcopy -O ihex a.out fw.hex

Before loading *fw.hex* to the device with ST-Link or OpenOCD, let's take a few minutes to analyze its content. Start with the two first lines::

    : 02 0000 04 0800 F2
    : 08 0000 00 0050002011000008 71

The first is a *04* record (Extended Linear Address), that means it sets the base address for consecutive *00* records, ``0800`` in this case. It looks familiar, especially when extended to 32 bits (that's how *04* records work): ``0x08000000``. It's the address of the flash memory!

The next record's type is *00*, that means data. This is exactly what will be loaded to the microcontroller. This particular line instructs the device programmer to flash 8 bytes at previously set address plus ``0x0000`` offset. Let me translate the payload from little endian to big endian: ``20005000 08000011``. Nice! This is top of RAM followed by the entry point! Let's execute one more command::

    arm-none-eabi-objdump -D a.out

On the top of the output, there should be something similar to this::

    08000010 <main>:
    08000010: 4a07    ldr r2, [pc, #28] ; (8000030 <main+0x20>)

The main function is actually at address ``08000010``, but it has been or'ed with ``1`` to produce odd result. The physical placement of the function didn't change at all, it's only how calls are made.

The code compiles, stack pointer and entry point addresses are at valid locations, everything looks promising. Flash it baby! It worked perfectly on my board, the green LED lit up as it was supposed to.

Limitations
+++++++++++

The linker script is undoubtedly working, and it can be even used with simple projects. But, there's a one caveat to be aware of: it's impossible to modify global variables. The script lacks ``.data`` section, thus the linker will put all globals right after ``.text`` section in a flash memory. As a consequence, they are readable, but not writable. It's clearly visible on the object dump of the binary::

    Disassembly of section .data:

    08000058 <a>:
    08000058:	deadbeef 	cdple	14, 10, cr11, cr13, cr15, {7}

To achieve this effect, I created a global variable: ``int a = 0xDEADBEEF``, and then compiled/linked the code again. By looking at the address, I can tell the variable has been put into the flash memory, so it effectively became read only.

It doesn't mean the variables can't be used in the code. This issue affects only global variables, but local variables are placed on the stack, so as long as only them are used, this linker script will work for such projects.

Simple Linker Script (SLS)
--------------------------

SSLS was meant to be just an example that linker script doesn't have to be complicated to do its primary job. In this section I'm going to describe a Simple Linker Script that truly can be used in projects, without giving up on basic language functionalities (like global variables).

MEMORY block
++++++++++++

In the previous example a so-called *location counter* was used to set the starting address of ``.text`` section. It's a sufficient approach for simple scripts, but it will quickly become a complete mess as more memory regions starts appearing in the linker script.

In a linker script there can be one, and only one block named **MEMORY**. This block should contain all memory regions relevant to the device and the project. The regions don't need to reflect microcontroller's memory layout exactly, however they are strongly correlated. The memory block is only for the developer and for the linker, it doesn't affect the target device in any way.

Let's define some basic regions that surely exist on a microcontroller::

    MEMORY
    {
        flash   (RX) : ORIGIN = 0x08000000, LENGTH = 128K
        sram    (RW) : ORIGIN = 0x20000000, LENGTH = 20K
    }

    ENTRY(main);

    SECTIONS
    {
        . = 0x08000000;
        LONG(0x20005000);
        LONG(main | 1);
        .text : { *(.text) }
    }

The syntax of entries in the memory block is self-explanatory.

- The first column is a name of a region, it can be virtually anything.
- The second column is a desired access, for flash memory it's *Read* and *eXecute*, for SRAM: *Read* and *Write*.
- The third column contains a start address of the region.
- The last column sets the maximum size of the region; this prevents from putting too much data into it. Linker will raise an error if it detects a memory overflow.

The regions can be placed and named freely. There can be, for example, two flash regions: *flash_1* starting from address ``0x08000000`` and *flash_2* at ``0x08001000``. Why? This could be due to various reasons, maybe there's a requirement to put a part of the code at a specific address.

And now it's time to reorganize the script a little::

    MEMORY {
        flash   (RX) : ORIGIN = 0x08000000, LENGTH = 128K
        sram    (RW) : ORIGIN = 0x20000000, LENGTH = 20K
    }

    ENTRY(main);

    SECTIONS
    {
        .text :
        {
            LONG(0x20005000);
            LONG(main | 1);
            *(.text)
        } > flash
    }

Here's a list of things I've done:

- Removed the direct location counter manipulation. Since the memory regions were introduced, it's no longer needed to set it manually.
- Moved the stack pointer and entry point values to the ``.text`` section.
- Told linker to put the ``.text`` section into the *flash* memory region.

Let's add one more output section. One of the drawbacks of SSLS was that it put global variables into the flash memory, because linker was not aware of other memory regions. ::

    MEMORY {
        flash   (RX) : ORIGIN = 0x08000000, LENGTH = 128K
        sram    (RW) : ORIGIN = 0x20000000, LENGTH = 20K
    }

    ENTRY(main);

    SECTIONS
    {
        .text :
        {
            LONG(0x20005000);
            LONG(main | 1);
            *(.text)
        } > flash

        .data :
        {
            *(.data)
        } > sram
    }

The newly added output section ``.data`` will include all ``.data`` sections from all object files, then the output section will be placed inside an SRAM memory. Compile, link and dump the object file to see what has changed ::

    Disassembly of section .data:

    20000000 <a>:
    20000000:	deadbeef 	cdple	14, 10, cr11, cr13, cr15, {7}

That looks good! This time the global variable is in the SRAM memory, so it is writable. Let's also take a look at the last few lines of the HEX file ::

    :02 0000 04 2000 DA
    :04 0000 00 EFBEADDE C4

The first record tells the device programmer to set the programming address to ``0x20000000`` and the next line tells it to write ``0xDEADBEEF`` in it. That looks go... Wait a minute! What it is trying to do is to flash data to SRAM, and that's not possible. Even if you could, everything will vanish at the first reset of the device.

Here comes the limitation of Simple Linker Script: global variables are writable, but they won't have their initial values when microcontroller starts. 

What about uninitialized variables?
+++++++++++++++++++++++++++++++++++

Global variables which were declared but not defined at the same time will end up in a ``.bss`` section. Such section wasn't defined in the linker script yet, but linker is smarter than me, and placed it right after the ``.data`` section, exactly where it should be. And here comes the second (and last) limitation of Simple Linker Script: uninitialized global variables won't be zeroed by default. Well, this is annoying but still tolerable.

Linker Script (LS)
------------------

It's time to write something that works in every aspect. The goal is to have a robust linker script which initialises variables with their predefined values, and zeroes those uninitialised.

Let's sum up what's missing:

- proper entry point and stack definitions,
- interrupt vectors,
- data initialisation.

Entry point and stack definitions
+++++++++++++++++++++++++++++++++

The addresses of entry point and the stack pointer were set directly in the linker script. This works fine but address of the entry point had to be ored so MCU knows that the function under this address uses Thumb instructions. This shouldn't be done manually, at least I didn't see such thing being done in any linker script.  

.. highlight:: c

Just out of curiosity, below the `main` function I've added a global variable pointing to the main method::

    void (*main_ptr)(void) = main;

.. highlight:: text

Now I compiled it and did the object dump. This is how the ``.data`` section looks like now::

    Disassembly of section .data:

    20000000 <main_ptr>:
    20000000:	08000009 	stmdaeq	r0, {r0, r3}

And the actual address of ``main``::

    08000008 <main>

.. highlight:: c

This looks promising. Apparently it's enough to create a pointer to a function, to get its address with the Thumb modifier. The last thing to do is to put this modified address on the beginning of the binary, and say bye-bye to manual bit manipulation. This can be done obviously by using a linker script with a little help of code. Somewhere below the main function, I've added the following lines::

    void (*prologue[]) (void) __attribute__((section (".prologue"))) = {
        (void (*)(void)) 0x20005000,
        main
    };

I feel obliged to explain each part of it.

``void (*prologue[]) (void)``
    This is a declaration of an array of pointers to functions which take nothing and return nothing.

``__attribute__``
    This is a special keyword for specifying additional properties of functions, variables, structures etc.

``section (".prologue")``
    This is a parameter to ``__attribute__`` which tells the compiler to put the related symbol (array in this case) into the section with the given name.

Putting it together: define an array of pointers to void functions and put it to the ``.prologue`` section, initializing it with two items – the first is the initial stack pointer and the second is the address of the ``main`` function.

.. highlight:: text

And now, let's force linker to put this tiny section on the beginning of the flash memory. ::

    MEMORY {
        flash   (RX) : ORIGIN = 0x08000000, LENGTH = 128K
        sram    (RW) : ORIGIN = 0x20000000, LENGTH = 20K
    }

    ENTRY(main);

    SECTIONS
    {
        .text :
        {
            KEEP(*(.prologue));
            *(.text)
        } > flash

        .data :
        {
            *(.data)
        } > sram
    }

The ``KEEP()`` function tells linker to exclude the supplied section from the garbage collection process. Linker would do that because the ``prologue`` array is not referenced anywhere in the code, so linker assumes it's unused.

As usual, let's to the object dump of the binary::

    Disassembly of section .text:

    08000000 <prologue>:
    8000000:	20005000 	andcs	r5, r0, r0
    8000004:	08000009 	stmdaeq	r0, {r0, r3}

    08000008 <main>:

It looks exactly as it should!

.. note::
    This article is still in progress. It lacks description how to zero ``.bss`` section and set up interrupt vectors.

----

.. target-notes::

.. _`ARM`: https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads
.. _`STM32F103RBT6`: https://www.st.com/resource/en/reference_manual/cd00171190-stm32f101xx-stm32f102xx-stm32f103xx-stm32f105xx-and-stm32f107xx-advanced-armbased-32bit-mcus-stmicroelectronics.pdf
.. _`ARM Branch instruction`: https://developer.arm.com/documentation/dui0802/a/Cihfddaf
.. _`Mastering the GNU linker script`: https://allthingsembedded.com/post/2020-04-11-mastering-the-gnu-linker-script/
