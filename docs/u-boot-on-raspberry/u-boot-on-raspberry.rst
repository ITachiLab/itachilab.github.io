.. highlight:: text

U-Boot on Raspberry
===================

Though it's not very common, it is sometimes desirable to replace the original Raspberry's bootloader with something more customizable like: `Das U-Boot`_. Having a handcrafted bootloader on an embedded system has a number of advantages:

- booting from other sources, like: network or USB,
- firmware upgrade,
- getting back to fail-safe state after messing up something,
- flexible kernel select,
- virtually anything one would want to do before the OS starts.

I had a hard time looking for some good knowledge source covering this topic. The only webpage that gave me lots of hints was `eLinux`_, though it had some outdated information. Eventually, I've managed to achieve the desired result, using the above source and going through many trials and errors.

Tools and stuff
---------------

Here's a list of things I've beein using during the development and testing:

Raspberry Pi Zero W
    The device I'm targeting.

SD card with Raspbian
    Something to boot.

Lubuntu
    Host machine where U-Boot is built. Any Linux distro will be okay.

USB to UART adapter
    Even though U-Boot supports HDMI and USB, it's more convenient to connect directly to Raspberry's serial port.

Prepare the host machine
--------------------------

Get the ARM toolchain
+++++++++++++++++++++

The first and foremost step is installation of the ARM toolchain. On distros like Ubuntu it's really straightforward::

    sudo apt install git build-essential crossbuild-essential-armhf

It might happen that the above set of packages won't be sufficient for the setup. In that case, just install what's missing, there's no magic here.

Clone U-Boot
++++++++++++

The best way to get the newest U-Boot is of course GitHub::

    git clone -b master --depth 1 https://github.com/u-boot/u-boot.git
    cd u-boot

The additional arguments to ``git`` command saves lots of time, as they instruct git to clone only the tip of the master branch.

Build U-Boot
------------

This step is pretty easy and shouldn't cause troubles. Just make sure appropriate cross compilation environment variable are present, so U-Boot will be built for ARM.

It's important to select *defconfig* appropriate to the target Raspberry. Available *defconfigs* are grouped inside the ``configs`` directory. In case the wrong *defconfig* will be used, U-Boot will simply fail to run. When everything is prepared, the magic spell to build U-Boot is::

    export CROSS_COMPILE=arm-linux-gnueabihf-
    make rpi_0_w_defconfig
    make -j8 -s

The compilation should be quite fast, it really depends on a CPU of the host. When it's finished without errors, a ``u-boot.bin`` file should be present in the current directory.

Before hitting the red button
-----------------------------

Everything required to write U-Boot to the SD card, and set it as the default boot target is ready. But before that can happen, there are a couple of additional steps.

Enable UART on Raspberry
++++++++++++++++++++++++

In order to communicate with U-Boot freely, UART on Raspberry must be enabled. This can be easily accomplished by modifying ``config.txt`` file living in the ``boot`` partition of the SD card. The following line should be added anywhere in the file::

    enable_uart=1

Know the Kernel command line
++++++++++++++++++++++++++++

When Raspberry boots the usual way, after the 3rd stage bootloader finishes its tasks, it runs ``start.elf`` which parses ``config.txt`` as one of its steps, and appends appropriate arguments to kernel's command line. They are not copied 1:1, that would be too simple. For example, ``enable_uart=1`` results in ``8250.nr_uarts=1`` being added to the kernel's command line.

.. note::

    For the sake of clarity: **8250** is a kernel module named "8250", **nr_uarts** is the module's option, and **1** is a new value of this option. This is equivalent of invoking: ``modprobe 8250 nr_uarts=1`` within the shell.

This is important to understand because U-Boot is going to be injected into the boot chain between ``start.elf`` and kernel image. Kernel won't receive these arguments anymore, they all go to U-Boot now, so U-Boot is responsible for supplying them to the kernel's command line. This sounds tricky, and is even trickier. 

The easiest, yet not so flexible method, is to peek the actual command line of the running system, and simply use it in U-Boot as the kernel's command line. Let's say the current Raspberry's configuration is satisfactory, and it's not supposed to be changed soon. If that's true, the current command line can be easily displayed with the following command, and saved somewhere for later::

    cat /proc/cmdline

.. caution::

    Manipulating the kernel's command line manually doesn't mean the ``config.txt`` file is no longer needed. Raspberry's CPU still needs it for example to enable UART or select image to boot.

Hit the red button
------------------

U-Boot is ready to be written to the SD card, and to be set as the boot source. In order to do that, ``u-boot.bin`` must be copied to the *boot* partition of the SD card, and an additional entry in ``config.txt`` must be added, so the board knows what to boot::

    kernel=u-boot.bin

The USB-UART adapter can now be connected to Raspberry with the following options:

:Baudrate: 115200
:Data bits: 8
:Stop bits: 1
:Parity: None
:Flow control: None

For minicom::

    sudo minicom -w -b 115200 -D /dev/tty[something]

As soon as Raspberry is powered on, it should put some U-Boot stuff on the terminal and do nothing more. The task has failed successfully, because there are a couple of additional steps to follow.

.. tip::
    If nothing pops up on the terminal, make sure the communication parameters are correct, and UART is enabled. If that seems to be okay, another cause could be messed up U-Boot build. Check correctness of defconfig, CROSS_COMPILE env, and the whole compilation process.


The extra steps
+++++++++++++++

There are a couple of things to fix in U-Boot so it can boot the kernel properly:

- Device Tree file is wrong.
- Kernel's boot arguments are not set.
- U-Boot can't find the image to boot.

Thankfully these are the only inconveniences, and the rest is a pure fun. I promise!

Fix Device Tree file
********************

Raspbian's kernel requires a Device Tree file to boot properly. This file must be loaded into RAM prior to booting, and the loading address shall be given to kernel. The DT file is read from the SD card, and its name is kept in ``fdtfile`` env variable. The current content of the variable can be examined like this::

    U-Boot> env print fdtfile
    fdtfile=bcm2835-rpi-zero-w.dtb

The problem here is that this file doesn't exist on the SD card, but there's another: ``bcm2708-rpi-zero-w.dtb``, so it must be used instead of the missing one::

    U-Boot> setenv fdtfile bcm2708-rpi-zero-w.dtb

Fix kernel boot args
********************

For most of the time, kernel needs some additional arguments, let it be location of the root file system, or configuration of the device. These additional parameters are called "command line" or simply "boot arguments (args)". In U-Boot, there's a dedicated env variable called *bootargs* that will be automatically passed to the kernel on boot.

The command line arguments obtained in `Know the Kernel command line`_ will be needed here. They must become the new value of the ``bootargs`` variable::

    U-Boot> setenv bootargs console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait

Fix kernel image
****************

The last thing to do is to point U-Boot to the valid kernel image that can be actually booted. The kernel image is on the SD card, but it must be inside RAM to be executed. In order to copy anything from an external source like the mentioned SD card, or a USB flash drive, the device must be first selected. Usually it is SD card, so the first step is to select it::

    U-Boot> mmc dev 0

The above command selects an MMC device at index 0. Raspberry has only one SD card slot, thus "0" is always a valid option. In contrast, USB can have multiple flash drives connected to it, and each will have a different index; it's up to the developer to select the correct one. All USB devices can be listed with this command::

    U-Boot> usb info

Let's get back on the track. When the proper MMC device is selected, any file from it can be loaded into RAM with just one command. In this case this will be the kernel image, and the Device Tree file, both of them has to be put somewhere into RAM to be usable. Fortunately, the correct load addresses are already set in U-Boot.

The right command to use is *fatload* and it does exactly what it means - it loads a file from a FAT partition::

    U-Boot> fatload mmc 0:1 ${kernel_addr_r} kernel.img
    U-Boot> fatload mmc 0:1 ${fdt_addres} ${fdtfile}

The syntax of the command is::

    fatload [device type] [device index]:[partition] [load address] [source file]

The first command copies ``kernel.img`` to the address stored in the ``kernel_addr_r`` env variable. The image file should be available on the first partition of the MMC 0 device. MMC 0 always points to an SD card slot on a Raspberry board, and the first partition is the *boot* partition. When the SD card is partitioned differently, the correct numbers has to be figured out beforehand.

The second command works exactly the same and copies the Device Tree file.

Boot!
-----

This time everything is prepared and should work flawlessly. The command to boot the kernel is given below, but **don't do this yet**. ::

    U-Boot> bootz ${kernel_addr_r} - ${fdt_addr}

``bootz`` is a command that boots a gzipped kernel image. The additional parameters are:

:`${kernel_addr_r}`: Environment variable with a memory address of where the kernel image was loaded.
:`-`: Boot without initrd.
:`${fdt_addr}`: Environment variable with a memory address of where Device Tree blob file was loaded.

Every (healthy) programmer at this point should start thinking: "Can all of that be automated somehow? This is so much work to do". Yes! The answer is: environment variables. ::

    U-Boot> setenv rpi_boot 'fatload mmc 0:1 ${kernel_addr_r} kernel.img; fatload mmc 0:1 ${fdt_addr} ${fdtfile}; bootz ${kernel_addr_r} - ${fdt_addr}'
    U-Boot> setenv bootcmd run rpi_boot
    U-Boot> saveenv

The first command sets a new ``rpi_boot`` env variable to the provided string. The string itself is a concatenation of commands given to U-Boot so far. The second command sets a new value for ``bootcmd`` variable, and the last command persists environment, meaning that the environment variables will be available after power loss.

Here's what will happen after the RPi is powered: When U-Boot's auto-start won't be interrupted by a key, it will run the default *boot* command. This command simply executes ``run bootcmd`` (``run`` treats arguments like commands), and that eventually executes ``run rpi_boot`` with the additional arguments.

Raspberry can now be powered off and on again in order to verify that everything works correctly. U-Boot should appear on the terminal for a short moment, and after a couple of seconds it should proceed with booting the kernel.

Extras
------

Dynamic kernel command line
+++++++++++++++++++++++++++

The most annoying and fishy step in this tutorial is deliberately hardcoding the kernel command line; this shouldn't work like that. The command line is generated automatically when Raspberry starts, so it also should be automatically given to the kernel, but U-Boot prevents that from happening. Moreover, it is so stubborn, that I couldn't find any official way of forcing it to pass the command line down to the kernel image.

I'm stubborn too...

.. caution::
    This is experimental! I can't guarantee it will work for everyone.

A funny thing will happen when the below command is executed in U-Boot shell::

    U-Boot> md.w 0x710 128

This command tells U-Boot to print 128 words starting from address ``0x710``. The ASCII column of the output should ring a bell::

    00000710: 6f63 6568 6572 746e 705f 6f6f 3d6c 4d31    coherent_pool=1M
    00000720: 3820 3532 2e30 726e 755f 7261 7374 313d     8250.nr_uarts=1
    00000730: 7320 646e 625f 6d63 3832 3533 652e 616e     snd_bcm2835.ena
    00000740: 6c62 5f65 6f63 706d 7461 615f 736c 3d61    ble_compat_alsa=
    00000750: 2030 6e73 5f64 6362 326d 3338 2e35 6e65    0 snd_bcm2835.en
    00000760: 6261 656c 685f 6d64 3d69 2031 6362 326d    able_hdmi=1 bcm2
    00000770: 3037 5f38 6266 662e 7762 6469 6874 313d    708_fb.fbwidth=1
    00000780: 3832 2030 6362 326d 3037 5f38 6266 662e    280 bcm2708_fb.f
    00000790: 6862 6965 6867 3d74 3237 2030 6362 326d    bheight=720 bcm2
    000007a0: 3037 5f38 6266 662e 7362 6177 3d70 2031    708_fb.fbswap=1
    000007b0: 6d73 6373 3539 7878 6d2e 6361 6461 7264    smsc95xx.macaddr
    000007c0: 423d 3a38 3732 453a 3a42 3636 453a 3a44    =B8:27:EB:66:ED:
    000007d0: 4337 7620 5f63 656d 2e6d 656d 5f6d 6162    7C vc_mem.mem_ba
    000007e0: 6573 303d 3178 6365 3030 3030 2030 6376    se=0x1ec00000 vc
    000007f0: 6d5f 6d65 6d2e 6d65 735f 7a69 3d65 7830    _mem.mem_size=0x
    00000800: 3032 3030 3030 3030 2020 6f63 736e 6c6f    20000000  consol
    00000810: 3d65 7474 5379 2c30 3131 3235 3030 6320    e=ttyS0,115200 c
    00000820: 6e6f 6f73 656c 743d 7974 2031 6f72 746f    onsole=tty1 root
    00000830: 503d 5241 5554 4955 3d44 3432 6434 3032    =PARTUUID=244d20
    00000840: 6337 302d 2032 6f72 746f 7366 7974 6570    7c-02 rootfstype
    00000850: 653d 7478 2034 6c65 7665 7461 726f 643d    =ext4 elevator=d
    00000860: 6165 6c64 6e69 2065 7366 6b63 722e 7065    eadline fsck.rep
    00000870: 6961 3d72 6579 2073 6f72 746f 6177 7469    air=yes rootwait
    00000880: 0000 e803 0000 0100 6f62 746f 6f6c 6461    ........bootload

Apparently this is the command line generated for the kernel, but never reaching it, because of U-Boot. It'd be nice to have it as an env variable, so it could be used for booting::

    U-Boot> setexpr.s bootargs *0x710

This command sets the env variable (*bootargs*) to the result of the expression, and the expression itself shall be treated as a string (setexpr**.s**). The expression is a memory pointer treated like a string, so it will contain all characters starting from address ``0x710`` all the way down until the 0x00 byte. Let's see the result::

    U-Boot> env print bootargs
    bootargs=coherent_pool=1M 8250.nr_uarts=1 snd_bcm2835.enable_compat_alsa=0 snd_bcm2835.enable_hdmi=1 bcm2708_fb.fbwidth=1280 bcm2708_fb.fbheight=720 bcm2708_fb.fbswap=1 smsc95xx.macaddr=B8:27:EB:66:ED:7C vc_mem.mem_base=0x1ec00000 vc_mem.mem_size=0x20000000  console=ttyS0,115200 console=tty1 root=PARTUUID=244d207c-02 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait

And now integrate it with the ``boot_rpi`` command::

    U-Boot> setenv boot_rpi 'setexpr.s bootargs *0x710; mmc dev 0; fatload mmc 0:1 ${kernel_addr_r} kernel.img; fatload mmc 0:1 ${fdt_addr} ${fdtfile}; bootz ${kernel_addr_r} - ${fdt_addr}'
    U-Boot> saveenv

Thanks to this, the kernel will always boot with proper command line options.

.. note::
    This won't work for the *dtoverlay* options in config.txt. Device Tree overlays are applied differently. This is of course possible in U-Boot, but requires extra work. 

----

.. target-notes::

.. _`Das U-Boot`: https://www.denx.de/wiki/U-Boot
.. _`eLinux`: https://elinux.org/RPi_U-Boot
