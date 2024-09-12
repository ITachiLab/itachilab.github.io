nRF52840 with CMSIS
===================

**nRF** chips manufactured by Nordic Semiconductor are known for their versatility when it comes to radio communication. A single chip can handle various communication protocols happening at 2.4 GHz frequency, for example: Bluetooth or ZigBee. Probably no one is crazy enough to implement stacks of these protocols from scratch unless there are some exceptional requirements. That's why it's a common patten to either use `nRF5 SDK`_, or more sexy recently `nRF Connect SDK`_ based on `Zephyr RTOS`_. I used to work with nRF5 SDK, but I have switched to the RTOS based SDK, and I must admin that I really like it.

Not every nRF-based project requires radio communication, sometimes it's all about controlling a bunch of GPIOs. Although using nRF for flashing an LED sounds like a massive overkill, it might happen that a development board with an nRF chip is the only available in a room. No 8-bit ATmegas within reach, just you and that scary board with countless components. Would a project based on Zephyr RTOS handle this? Definitely. Would it be an overkill level 1000? Absolutely. Can it be lighter? Sure!

CMSIS
-----

Everyone knows CMSIS, right? It's just a bunch of headers and source codes to make bootstrapping ARM-based projects less painful. CMSIS exposes an interface of very basic functionalities which are the same across different ARM processors, an example could be a set of functions for controlling NVIC or SysTick timer. Thanks to this, a code written for Cortex-M4 should also work with Cortex-M3, or Cortex-M0. This of course applies only to the common stuff, and any device-specific logic won't simply work when moved directly to another device, but that's perfectly enough.

So, can it be used with nRF? Of course! They are based on ARM chips, that means the low-level behavior is consistent with other ARM-based solutions. Let's see that it's not that hard to setup a very simple working project.

Requirements
------------

There are only two requirements: `CMSIS`_, the `ARM GCC`_, and of course a board with nRF chip; mine is `nRF52840 DK`_.

Project files
-------------

Makefile
++++++++

To keep it simple stupid, the project is built around a Makefile. So, here is the Makefile:

.. code-block:: Makefile
   
   CMSIS_DIR = /opt/CMSIS_5-5.9.0
   ARMCM4_DIR = $(CMSIS_DIR)/Device/ARM/ARMCM4
   CMSIS_SRCS = \
   	 $(ARMCM4_DIR)/Source/startup_ARMCM4.c \
   	 $(ARMCM4_DIR)/Source/system_ARMCM4.c
   CMSIS_INCLUDES = \
   	 $(ARMCM4_DIR)/Include \
   	 $(CMSIS_DIR)/CMSIS/Core/Include

   .PHONY: clean flash

   flash: main.hex
   	nrfjprog -f nrf52 --program $^ --verify --reset --sectorerase

   main.hex: main.elf
   	arm-none-eabi-objcopy -O ihex $^ $@
   
   main.elf: main.c
   	arm-none-eabi-gcc \
   		-mthumb \
   		-mcpu=cortex-m4 \
   		-mfloat-abi=hard \
   		--specs=nosys.specs \
   		-Wl,-Tscript.ld \
   		-D ARMCM4_FP \
   		$(foreach dir,$(CMSIS_INCLUDES),-I$(dir)) \
   		-o $@ \
   		$(CMSIS_SRCS) $^

   clean:
   	rm -f  *.elf *.hex

This is only a very basic Makefile. Possibly I miss a couple of additional GCC options which will make the binary smaller and optimized better but it's not the goal of this article. 

.. caution:: It's important to select a correct processor type, and use source codes and headers from appropriate directories. The compilation flags must match too. The above Makefile is targeting nRF52840, which is based on the Cortex-M4.

Linker script
+++++++++++++

I copied a linker script from CMSIS (``<CMSIS>/Device/ARM/ARMCM4/Source/GCC/gcc_arm.ld``) to the project's directory, and changed sizes of memories as following::

   __ROM_BASE = 0x00000000;
   __ROM_SIZE = 0x00100000;
   
   __RAM_BASE = 0x20000000;
   __RAM_SIZE = 0x00040000;
   
   __STACK_SIZE = 0x00000400;
   __HEAP_SIZE  = 0x00000C00;

Sizes of a stack and a heap can be chosen arbitrarily. One can decide how much memory is needed for both, and a linker will show an error whenever any of them is overflowed. Other values must match values present in a chip's datasheet, or else the code will be flashed to a wrong place in a memory.

main.c
++++++

The last element of the puzzle is obviously the code itself. Mine doesn't do much, I just wanted to test whether it works, so what would be better than just turning on an LED? Since there's no SDK on board, I have to figure out correct GPIO addresses by myself. On my board the LEDs are connected to pins ``P0.13 - P0.16``. A quick look to the `documentation <GPIO docs_>`_ reveals that the **P0** is based at ``0x50000300``, the register responsible for a pin direction has offset ``0x514``, and the one for output state has ``0x504``.

Good, now let's turn a single LED. To do this the GPIOs have to be obviously in the output mode, and not obviously cleared. Why? Because LEDs on the board are tied to VDD and to the port, so the port must sink the current.

.. code-block:: c

    #include <stdint.h>

    int main() {
        uint32_t *dir = (uint32_t *) 0x50000514;
        uint32_t *out = (uint32_t *) 0x50000504;

        *dir = (0b1111 << 13);
        *out = ~(1 << 13);

        while(1) {}
    }

Yeah, but GPIOs are easy, other things are probably complicated as hell, right? Some of them are indeed, no one would want to play with the radio peripherals on pure registers without a very good reason. I'm not saying it's impossible, everything is possible, it just takes precious time... Speaking of time, below is a classical example of a blinking LED built on a timer peripheral. It clearly shows that even more complex peripherals are fairly easy to operate with raw register access.

.. code-block:: c

    #include <stdint.h>
    #include <system_ARMCM4.h>
    #include <ARMCM4_FP.h>
    
    #define GPIO_BASE       0x50000000
    #define TIMER_BASE      0x40008000
    
    #define TIMER(n, o) static uint32_t * const timer_ ## n = (uint32_t *) (TIMER_BASE + o)
    #define GPIO(n, o) static uint32_t * const gpio_ ## n = (uint32_t *) (GPIO_BASE + o)
    
    GPIO(dir, 0x514);
    GPIO(out, 0x504);
    
    TIMER(start, 0x0);
    TIMER(bitmode, 0x508);
    TIMER(prescaler, 0x510);
    TIMER(intenset, 0x304);
    TIMER(cc, 0x540); 
    TIMER(event, 0x140);
    TIMER(shorts, 0x200);
    
    void Interrupt8_Handler() {
       *gpio_out ^= (1 << 13);
       *timer_event = 0;
    }
    
    int main() {
        *gpio_dir |= (0b1111 << 13);
        *gpio_out |= (0b1111 << 13);
    
        *timer_prescaler = 7;
        *timer_bitmode = 2;
        *timer_intenset = 1 << 16;
        *timer_cc = 125000;
        *timer_shorts = 1;
    
        NVIC_ClearPendingIRQ(Interrupt8_IRQn);
        NVIC_EnableIRQ(Interrupt8_IRQn);
    
        *timer_start = 1;
    
        while(1) {}
    }

The code is really simple, it just looks complicated due to my macros (I'm too lazy to copy-paste-change registers constants). In the main method I'm configuring the timer to fire a compare event every second. The formula for calculating the interrupt frequency:

.. math::

    f_i = \frac{16\text{MHz}}{CC\cdot 2^P} = \frac{16000000}{125000\cdot 2^7} = 1\text{Hz}

The misty ``*timer_shorts = 1`` enables a shortcut between a compare event and a clear task, i.e. when the compare event happens, the timer is cleared immediately.

Final thoughts
--------------

I was prepared for a harder work but I must admit I had more troubles with doing the analogous stuff with **STM32F103**. Obviously, if I had to dig deeper and code more complex things, doing this at such low level would be cumbersome. But, if the application is supposed to be simple, like some basic readings, writings, UART, etc., then I will definitely think twice before I begin the project with nRF SDK or nRF Connect on board.

Don't get me wrong, I really like the concept of nRF Connect, I'm currently developing a bigger project on it, and it serves me very well.

---

.. target-notes::

.. _`nRF5 SDK`: https://www.nordicsemi.com/Products/Development-software/nrf5-sdk
.. _`nRF Connect SDK`: https://www.nordicsemi.com/Products/Development-software/nrf-connect-sdk
.. _`Zephyr RTOS`: https://docs.zephyrproject.org/latest/index.html
.. _`ARM GCC`: https://developer.arm.com/downloads/-/gnu-rm
.. _`CMSIS`: https://www.arm.com/technologies/cmsis
.. _`nRF52840 DK`: https://www.nordicsemi.com/Products/Development-hardware/nRF52840-DK
.. _`GPIO docs`: https://infocenter.nordicsemi.com/topic/ps_nrf52840/gpio.html?cp=5_0_0_5_8
