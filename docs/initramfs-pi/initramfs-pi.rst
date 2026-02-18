.. highlight:: text

Raspberry Pi running from initramfs
===================================

In this article we are going to do really cool stuff (as always, aren't we?). How about having a really small Kernel for Raspberry that runs entirely from its initial RAM file system, and doesn't even need an SD card once it's up? An example application could be some metering IoT platform that only reads data from a bunch of I2C or SPI devices and sends that to the cloud. When you build device like this, you really don't need all this fancy stuff shipped with Raspbian. In fact, you only need a bunch of drivers and binaries. All of that is small enough to fit in RAM and still leave lots of space for running programs.

Flight plan
-----------

This article will be lengthy, I'm not gonna lie. Here's a short list of long things we are going to do:

.. topic:: Setup a development environment

    It's rather obvious we need some build tools. This time we are going to use two different toolchains -- one for building the Kernel, and second for building other stuff that will run under this kernel.

    .. attention::
        Using different toolchain for building the Linux apps might be relevant only for Raspberries powered by ARMv6 chips (like mine Raspberry Pi Zero W). I didn't test that, but if you have Raspberry with ARMv7, you might want to try using the same toolchain for the apps.

.. topic:: Prepare Raspberry Pi

    In order to run our custom Kernel, we have to change a couple of things on the `boot` partition.

.. topic:: Prepare a minimalist Kernel

    Depending on our needs, we can tailor the Kernel to only contain necessary modules. Media or HID drivers? Who needs that on the metering platform?!

.. topic:: Build BusyBox

    When it comes to embedded devices, I mean, REAL embedded devices, BusyBox is your best friend. It contains all the tools you need to setup a simple CLI for managing your platform.

.. topic:: Prepare an initial RAM file system (initramfs)

    This will be the hardest part. Kernel is one thing, but the root file system is a completely different story. ``/dev``, ``/etc`` or ``/lib`` aren't going to magically appear. The responsibility of creating these and other directories lays on you, sorry.

Sounds like we have a plan. Shall we start?

Setup a development environment
-------------------------------

For building the Kernel
+++++++++++++++++++++++

Let's start with obtaining the stuff we actually want to compile, the most important of course will be `Raspbian`_. The following command will clone only the head branch and only the tip of it; we don't need the whole history::

    git clone --depth 1 --single-branch https://github.com/raspberrypi/linux.git

When it comes to compiling the Kernel, it's beautifully described in the `Kernel documentation`_. It's not that hard, really. First, you need to install a bunch of tools::

    sudo apt install git bc bison flex libssl-dev make libc6-dev libncurses5-dev

After that, you have to decide what cross toolchain you need. The choice depends on Raspberry version you are targeting. For this article I'm going to use *Raspberry Pi Zero W*, so the proper toolchain is the one targeting 32-bit platforms. ::

    sudo apt install crossbuild-essential-armhf

For 64-bit Pies the command doesn't differ much::

    sudo apt install crossbuild-essential-arm64

For building other stuff
++++++++++++++++++++++++

As mentioned earlier, this step might be relevant only for ARMv6 Raspberries. If you have one, you need another toolchain for building the Linux apps that will run under your custom Kernel. Thankfully, there's a place where you can download precompiled toolchains, so you don't have to create them on your own: `Raspberry cross-compilers`_.

At the time of writing this article, the newest Raspbian is based on Debian 11 (Bullseye), so enter the directory with that name. Next, you have to choose a GCC version. Take the newest, and in case of troubles, you can try other versions later. The last step is selecting the proper Raspberry (I'm choosing  *Raspberry Pi 1, Zero* here). That's it! You can now download the toolchain, extract it, and keep somewhere until we need it.

Directory structure
+++++++++++++++++++

I like keeping all related stuff together, so I organized my workspace as follows::

    pi-workspace/
    ├─ linux/
    ├─ initramfs/
    │  ├─ initramfs.cpio-config
    │  ├─ content/
    ├─ cross-pi/
    ├─ extra/
    │  ├─ busybox/

:linux: Directory with Raspbian repo.
:initramfs.cpio-config: Configuration file for the script which will create a CPIO archive with initramfs contents.
:content: The actual content of initramfs. It will be used together with the configuration file.
:cross-pi: Cross toolchain for building stuff other than Kernel.
:extra: Extra tools and software, BusyBox is an example here.

Prepare Raspberry Pi
--------------------

We start from downloading the Raspbian Lite image and writing it onto an SD card. Use any method you like, it doesn't matter. Once it's done, we have to tweak a few things.

Changes in config.txt
+++++++++++++++++++++

At the end of the file, add the following lines::

    kernel=zImage
    enable_uart=1

The first line sets Kernel file name to ``zImage``. This file doesn't exist yet, we are going to create it soon. The second line enables serial console. This will be the preferred and only way of communicating with Raspberry directly.

Changes in cmdline.txt
++++++++++++++++++++++

While modifying ``config.txt`` isn't anything extraordinary, ``cmdline.txt`` is rarely touched. This file contains parameters that will be passed to Kernel when it's booting. It's like passing command line arguments to programs.

The default cmdline has lots of stuff we don't need. These are:

:root: This is a parameter that points to the device with a root file system. Since we are building Raspberry that runs entirely from initramfs, this will be the root file system.
:rootfstype: A type of the file system of the root device. Since we are not using any root device, this can be safely removed.
:fsck.repair: Controls fsck behavior. Again, we are not planning to use any file system, so this can be removed too.
:rootwait: Makes Kernel wait for the root device to be available. Not needed too.
:quiet: Suppresses Kernel messages while booting. When working with our hand-crafted Linux from scratch you indeed want to see Kernel messages.
:init: Selects the initial program to run when Kernel is booting. If this is removed, Kernel will try to find ``init`` program in the root directory of initramfs and this is exactly what we want.
:console=tty1: Remove only this, the second occurrence of ``console``. The purpose of this option is widely described on the page dedicated to `Kernel serial console`_. Shortly speaking: leaving only the first ``console`` setting will result in both Kernel messages and anything written to ``/dev/console`` being sent through Raspberry's UART. Until we equip our tiny Linux with something that can manage TTYs (like BusyBox), this is the only way of sending program output to UART.

After all this cleaning, it looks like the only stuff we need in the command line is::

    console=serial0,115200

Minimalist Kernel
-----------------

The fun part begins -- we are going to configure the Kernel. The best choice is to start with the default config for Raspberry and then tailor that to your needs. It's easier to work on something that can be booted out of the box, then proceed with removing unused stuff, than to spent the rest of your life wondering why your Kernel doesn't boot.

Without much talking, navigate your console to the directory with Raspbian and execute the following commands::

    KERNEL=kernel
    make bcmrpi_defconfig

.. caution::
    The defconfig for your Raspberry might be different, there's a page that describes `Raspberry Kernel configuration`_, it also points out what default configuration is suitable for each Raspberry.  The one I'm using here is suitable for Raspberry 1, Zero, Zero W and Compute Module 1.

When the default config is ready, you can proceed with a more detailed configuration through `menuconfig`::

    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig

Or, for 64-bit Kernels::

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig

I spent a good hour or two removing unnecessary modules, in order to make Kernel small, you can find my ``.config`` xref:attachment$kernel.config[in attachments]. In general, I did the following:

- disabled modules subsystem, so everything is built into the Kernel binary;
- disabled drivers for stuff I will never use, like: HID, media, graphics, amateur radio, wired network and many more;
- removed support for file systems.

Minimalist initramfs
--------------------

Though Kernel can boot without any initramfs on board, and we could just proceed with building the Kernel image now, but wouldn't it be cool to run a simple initial program, and see everything working before we begin with more advanced topics? I bet it would, and it isn't that hard.

Before you continue with this article, I really recommend getting known with `Rootfs how-to`_, author explains initramfs, its purpose and gives a bunch of useful hints for beginners. Trust me, you won't regret a single minute spent on this article.

Prepare a configuration file
++++++++++++++++++++++++++++

To create our initramfs, we will use the approach based on a configuration file. This gives the most flexibility and makes doing any changes way more easier than manipulating files in a directory (especially when it comes to changing permissions and creating device nodes).

Our first configuration file is going to be super simple. It will contain just three lines, instructing the packaging script to put the initial program into the root of the initramfs and create ``/dev/console`` device.

.. code-block::
    :linenos:

    dir /dev 755 0 0 <1>
    nod /dev/console 644 0 0 c 5 1 <2>
    file /init ../initramfs/content/init 755 0 0 <3>

1. Create ``/dev`` directory.
2. Create a character device ``/dev/console``. This step is required to write anything to the console from within the initial program.
3. Copy ``init`` program from the given source path to the root of the initramfs. The source path is relative to the directory the Kernel is built from. Here I assume the directory structure is the same as described on the beginning of the article. Permissions are typical for any executable.

There's only one small detail left -- we don't have any initial program available! Thankfully it can be as simple as "Hello, World!".

Prepare a simple initial program
++++++++++++++++++++++++++++++++

Create a new file ``init.c`` with the following content:

.. code-block:: c

    #include <stdio.h>
    #include <unistd.h>

    int main() {
        printf("Hello, World!");
        sleep(9999);
        return 0;
    }

.. tip::
    The ``sleep(9999)`` at the end is needed to avoid ugly Kernel panics caused by initial program finishing its execution. When the initial program is started by Kernel, it is assigned PID 1. A program with this PID must not be terminated.

The initial program has to be compiled with an appropriate toolchain, as described `on the beginning <For building other stuff_>`_. For my Raspberry Pi Zero W, I'm going to use the additional toolchain for ARMv6. ::

    $ export PATH=/home/fooser/pi-workspace/cross-pi/bin:$PATH
    $ arm-linux-gnueabihf-gcc -static -o init init.c

In order to be sure that I'm using the correct toolchain, I prepended it to the PATH variable. I also checked the binary using ``readelf`` to see if the target architecture matches the Raspberry's architecture. ::

    $ readelf -A init

    Attribute Section: aeabi
    File Attributes
      Tag_CPU_name: "6"
      Tag_CPU_arch: v6
      Tag_ARM_ISA_use: Yes
      Tag_THUMB_ISA_use: Thumb-1
      Tag_FP_arch: VFPv2
      Tag_ABI_PCS_wchar_t: 4
      Tag_ABI_FP_rounding: Needed
      Tag_ABI_FP_denormal: Needed
      Tag_ABI_FP_exceptions: Needed
      Tag_ABI_FP_number_model: IEEE 754
      Tag_ABI_align_needed: 8-byte
      Tag_ABI_align_preserved: 8-byte, except leaf SP
      Tag_ABI_enum_size: int
      Tag_ABI_VFP_args: VFP registers
      Tag_CPU_unaligned_access: v6

The last step is to move the compiled binary to the directory with initramfs contents.

Select CPIO configuration file as the initramfs source
++++++++++++++++++++++++++++++++++++++++++++++++++++++

While being in Kernel menuconfig, go to *General setup*, find *Initramfs source file(s)* and set the path to: ``../initramfs/initramfs.cpio-config`` (or other, if you organized your directory differently).

Build and run Kernel
--------------------

If everything is ready, it's time to build the Kernel. Invoke the below command and go make yourself a coffee, the compilation process can take 15-20 minutes, depending on your machine and on a number of things you left enabled in Kernel config. ::

    $ make -j4 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage

When it's done, the gzipped Kernel image can be found at *arch/arm/boot/zImage*. Copy this file to the *boot* partition of the SD card you've prepared earlier and try booting Raspberry from it. If you did everything properly, on the Raspberry's serial output you should see Kernel messages appearing and finally a "Hello, World!" text.

Congratulations, you've just created a valid initramfs, AND an initial program! It doesn't do much, but we really do not want to make it do more. It's not our task to write any sort of such stuff because we already have it covered by BusyBox.

BusyBox
-------

BusyBox is a set of Linux utilities you need to have to survive in the Linux world, especially when this world is embedded. All commands you usually want to be available, like: ``cat``, ``ls``, ``mv``, ``ip`` etc. are incorporated in BusyBox. Sure you can compile each of them manually and put to appropriate ``/bin`` or ``/sbin`` directory in initramfs, but this will take definitely too much time. BusyBox has all of that common commands out-of-the-box.

Besides being a big pile of useful tools, BusyBox offers everything you would expect from a typical Linux shell. BusyBox will be your initial program and sign-in facility too. No surprise the authors call it: "*The Swiss Army knife of Embedded Linux*".

Get sources
+++++++++++

The latest BusyBox sources can be downloaded from the `BusyBox`_ official site. Download the desired package and extract it anywhere you want. In my case, I have it in ``extra/busybox`` directory inside the project workspace. And that's all, the next step will be configuration of BusyBox's features.

Configure features
++++++++++++++++++

.. caution::
    Before you proceed, make sure a toolchain appropriate for building Linux apps is present in your PATH. This should be the same toolchain you used for the initial program earlier.

BusyBox can be configured in a similar manner we configured Kernel. You can start with one of the default configurations, and tailor it to your needs (that's what I did). To list possible make targets, execute: ``make help``. If you don't care about BusyBox size, and you feel comfortable with having everything, you can go with ``make defconfig`` which will create the largest generic configuration.

Whatever config you chose, there are still two small things you'd like to change in the configuration, so run ``make menuconfig``, go to *Settings* and change the below options to suggested values:

Build static binary (no shared libs)
    Mark that as enabled. Thanks to this, you will save some time on finding libraries required by BusyBox and copying them to initramfs.

Cross compiler prefix
    Set that to: ``arm-linux-gnueabihf-``.

----

.. target-notes::

.. _`Raspbian`: https://github.com/raspberrypi/linux
.. _`Kernel documentation`: https://www.raspberrypi.com/documentation/computers/linux_kernel.html.
.. _`Raspberry cross-compilers`: https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/
.. _`Kernel serial console`: https://www.kernel.org/doc/html/v4.17/admin-guide/serial-console.html
.. _`Raspberry Kernel configuration`: https://www.raspberrypi.com/documentation/computers/linux_kernel.html#kernel-configuration
.. _`Rootfs how-to`: https://landley.net/writing/rootfs-howto.html
.. _`BusyBox`: https://www.busybox.net/downloads/
