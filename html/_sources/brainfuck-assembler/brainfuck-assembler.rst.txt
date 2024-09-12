.. highlight:: text

Brainfuck Assembler (BFA)
=========================

I believe most of the readers have heard about *Brainfuck* programming language. This language serves two main purposes:

* it's indeed a programming language,
* fucks a brain.

Sounds like it does exactly what the name suggests. Let's consider this "Hello World" example::

    ++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.

Looks ugly and, what's worse, it works somehow. For those who doesn't believe, I really encourage to try this out in the `Brainfuck online interpreter`_, which should be kept opened anyway in a new tab as it will come in handy for the duration of this article.

Brainfuck is based on a bunch of primitive machine commands, which are apparently sufficient to make Brainfuck a Turing complete language. In other words: despite causing a permanent brain damage, Brainfuck can be used to write fully fledged applications (theoretically).

For obvious reasons - DRY, laziness, me being me - I'm not going to describe how Brainfuck actually works, everything is nicely explained on `Brainfuck Wikipedia`_. The goal of this article is different: create high level assembler for Brainfuck. Why? For fun of course!

Hands on
--------

"High level assembler" - sounds ridiculous, it is ridiculous, but look at that: if treat Brainfuck as a machine code, then Brainfuck's interpreter can be considered a platform providing a memory and very limited CPU that understands Brainfuck's Machine Code. On this memory a stack can be constructed, and a single CPU register can be emulated (only one, keeping more of them will be burdensome).

Brainfuck Primitive Architecture (BPA)
--------------------------------------

The assumptions of BPA are as follows:

Memory
    Starts at ``0x0`` and is limited only by interpreter's implementation.

Stack
    Top of the stack is initially set to -1, meaning that it's an invalid operation to read from the stack if there's nothing on it. Every push operation first increases the stack pointer (SP) and then writes the data. SP is always equal to the *current interpreter's data pointer - 1.*

Register "r0"
    This is the only register. It always lives under the current interpreter's data pointer, meaning that it is a part of the memory. Due to this, care must be taken when pushing new thins onto the stack as they can possibly overwrite precious data in r0.

Forced flow of operations
    BPA's CPU instruction pointer can't be modified manually.

Probably the most painful part will be maintaining the stack and the r0 register. Although the concept of the stack is entirely virtual and optional, having it in our toolbox will make writing codes in BPA ASM way easier than without it.

Syntax and reference
--------------------

Before we start describing the instruction set, let's define a bunch of simple keywords used in the following section.

:r0: The only register we have.
:<con>: Any 8-bit constant value.
:<mem>: A location in memory. This can be either a variable (``$example``) or a stack pointer (``$sp``). An additional offset can be added or subtracted (``$example - 5``).

.. NOTE::
    ``$sp`` is a built-in variable that always points to the top of the stack. Declaring a variable with the same name will lead to an error.

Simple arithmetic
+++++++++++++++++

Simple arithmetical operations like addition or subtraction can be effortlessly constructed using the Brainfuck's increment and decrement commands.

+------------------------+-------------------------------------+----------------------------------------------------+
| Instruction            | Machine Code                        | Description                                        |
+========================+=====================================+====================================================+
| ``inc r0``             | ``+``                               | Increase value of r0 register.                     |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``dec r0``             | ``-``                               | Decrease value of r0 register.                     |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``add r0, <con>``      | ``+`` repeated *con* times.         | Increase value of r0 register by a constant value. |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``sub r0, <con>``      | ``-`` repeated *con* times.         | Decrease value of r0 register by a constant value. |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``inc [<mem>]``        | Increase value of a variable on the stack.                                               |
+------------------------+------------------------------------------------------------------------------------------+
| ``dec [<mem>]``        | Decrease value of a variable on the stack.                                               |
+------------------------+------------------------------------------------------------------------------------------+
| ``add [<mem>], <con>`` | Increase value of a variable on the stack by a constant value.                           |
+------------------------+------------------------------------------------------------------------------------------+
| ``sub [<mem>], <con>`` | Decrease value of a variable on the stack by a constant value.                           |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``zero``               | ``[-]``                             | Zeroes the *r0* register.                          |
+------------------------+-------------------------------------+----------------------------------------------------+
| ``zero [<mem>]``       | Zeroes a variable on the stack.                                                          |
+------------------------+------------------------------------------------------------------------------------------+

Manipulating a variable on the stack
************************************

Operations involving manipulation of variables on the stack are pretty similar. All of them consist of three steps:

1. set the data pointer at the desired memory location,
2. perform arithmetic operation,
3. go back to the original memory location.

The first step is always a bunch of ``<`` operations, depending on what memory location has been chosen. The second step is the arithmetic operation. The last step is an exact reverse of the first.

Let's say a *foo* variable is located at 3rd memory cell and the current data pointer is at 6th. The instruction: ``inc [$foo]`` will be assembled to::

    <<< + >>>

All other arithmetic operations are analogical:

.. code-block:: text
    :linenos:

    <<< - >>>
    <<< +++ >>>
    <<< ---- >>>
    <<< [-] >>>

1. ``dec [$foo]``
2. ``add [$foo], 3``
3. ``sub [$foo], 4``
4. ``zero [$foo]``

Stack operations
++++++++++++++++

This section requires a little more in-depth look than the simple arithmetics. When memory operations are involved, we are responsible for maintaining its consistency.

+----------------+---------------------------------------------------------------------------------------------------------------------------------+----------------------------------+
| Instruction    | Machine Code                                                                                                                    | Description                      |
+================+=================================================================================================================================+==================================+
| ``pop``        | ``<``                                                                                                                           | Popping from the stack.          |
+----------------+---------------------------------------------------------------------------------------------------------------------------------+----------------------------------+
| ``push r0``    | ``+>[-]>[-]<<[->+>+<<]>>[-<<+>>]<+`` or ``>``                                                                                   | Pushing onto the stack.          |
+----------------+---------------------------------------------------------------------------------------------------------------------------------+----------------------------------+
| ``push <con>`` | ``+>[-]<[->+<]+``, then repeat ``+`` *con* times, then ``>``; or sometimes: ``[-]``, then repeat ``+`` *con* times, then ``>``. | Pushing constant onto the stack. |
+----------------+---------------------------------------------------------------------------------------------------------------------------------+----------------------------------+

Popping from the stack
**********************

This is the shortest operation that does much.Its purpose is to get the value from the top of the stack and move it to the r0 register. Since the r0 register lives in the memory and is exactly one memory cell right to the top of the stack, the data pointer can be simply decreased, so the r0 register contains the previous stack's top.

Pushing r0 onto the stack
*************************

And here it is -- the first more complex instruction. Its purpose is to put the register r0 onto the stack, while keeping the value in the register. Sounds simple, but involves lots of copying and copying isn't simple in Brainfuck. Let's divide and conquer this task.

The first thing we have to take care of is to move r0 to the next memory cell, because the current will become a new stack's top. In Brainfuck we can't just copy values between cells, but we can smartly loop decrease and increase operations. Copying is just using the current cell value as a loop condition, and increasing another cell by one on each loop iteration. Copying the current cell to the next will look like this::

    [->+<]

This tells Brainfuck to enter the loop if the current cell's value is not zero, then decrease the current cell's value, go to the next cell, increase its value, go to the source cell and go back to the loop's start. This will work, but has two caveats:

- it won't copy, it will move the source value, because the source value is used as a loop counter;
- the target cell must be zero.

To tackle the first problem, we have to introduce a temporary memory cell which will be increased along with the target cell. After we move the value from source to target, the temporary cell will be used to restore the source cell's value. This also means that only the target cell must be zero, but the temporary cell too. ::

    >           ; Go to the target cell.
    [-]         ; Zero it.
    >           ; Go to the temporary cell.
    [-]         ; Zero it.
    <<          ; Go back to the source cell.
    [->+>+<<]   ; Until zero, decrease the source cell's value, go to the target cell, increase it, go to the temporary cell, increase it, and go back to the source cell.
    >>          ; Go to the temporary cell.
    [-<<+>>]    ; Until zero, decrease the temporary cell's value, go to the source cell, increase it, go to the temporary cell.

When the above sequence finishes, the source and the target cell will have the same value. To complete the whole operation for our purposes, the data pointer must be decreased to point at the new r0 position, thus the final form will be::

    >[-]>[-]<<[->+>+<<]>>[-<<+>>]<

Possible optimization
^^^^^^^^^^^^^^^^^^^^^

In some circumstances, the push operation can be significantly optimized. Consider the following pair of instructions::

    push   r0
    mov    r0, 15

(We didn't talk about ``mov`` yet, but we will.)

First, the r0 is pushed onto the stack, then r0 is being written a constant value. In such case, we don't have to maintain the r0's value, because it will be overwritten anyway, thus the whole copying thing can be omitted and the data pointer can be simply increased. As a consequence, the new stack's top will be the old r0, and the new r0 will be some zero or random value that will be soon filled in with a data.

Pushing constant onto the stack
*******************************

This will be slightly simpler than pushing the register, because we don't need to copy the r0 to two places then copy it again to the stack's top. ::

    >           ; Go to the target cell.
    [-]         ; Zero it.
    <           ; Go to the source cell.
    [->+<]      ; Until zero, decrease the source cell, go to the target cell, increase it, and go to the source cell.
    +++...      ; Increase the source cell as many times as needed to achieve the desired value.
    >           ; Set the data pointer to the new r0 (target cell).

And again, in some circumstances, the above operations can be optimized::

    [-]         ; Zero the source cell.
    +++...      ; Increase the source cell as many times as needed to achieve the desired value.
    >           ; Set the data pointer to the new r0 (target cell).

This is possible only if r0 is to be written with some value, but the old value won't be used in the meantime.

Copying (moving) operations
+++++++++++++++++++++++++++

We've already discussed copying values between cells, but these were rather side effects of other instructions. In this section we are going to do some intentional copying.

+------------------------+-------------------------------------------+-----------------------------------------------------------------------+
| Instruction            | Machine Code                              | Description                                                           |
+========================+===========================================+=======================================================================+
| ``mov r0, <con>``      | ``[-]``, then ``+`` repeated *con* times. | Zero r0 register and increase its value until the desired is reached. |
+------------------------+-------------------------------------------+-----------------------------------------------------------------------+
| ``mov r0, [<mem>]``    | Copying memory to ``r0``.                                                                                         |
+------------------------+-------------------------------------------------------------------------------------------------------------------+
| ``mov [<mem>], r0``    | Copying ``r0`` to memory.                                                                                         |
+------------------------+-------------------------------------------------------------------------------------------------------------------+
| ``mov [<mem>], <con>`` | Copying constant to memory.                                                                                       |
+------------------------+-------------------------------------------------------------------------------------------------------------------+

Copying memory to r0
********************

This is another kind of instruction that requires using a temporary cell to back up the source data. Suppose we'd like to execute the following instruction: `mov r0, [$sp - 3]`. Then, the following set of Brainfuck commands shall be executed:

.. code-block:: text
    :linenos:

    [-]
    >
    [-]
    <<<<<
    [->>>>+>+<<<<<]
    >>>>>
    [-<<<<<+>>>>>>]
    <

1. Zero r0 register.
2. Go to the temporary cell.
3. Zero the temporary cell.
4. Go to the source cell.
5. Repeat the loop until the source cell is zero. In each loop iteration: decrease the source cell, go to the r0 register, increase it, go to the temp cell and also increase it. Before repeating the loop, go back to the source cell.
6. Go to the temp cell.
7. Repeat the loop until the temporary cell is zero. In each loop iteration: decrease the temporary cell value, go to the source cell, increase it and go back to the temporary cell. Repeat the loop.
8. Set the data pointer at r0 register.

The only variable parts are the ones moving the data pointer back and forth to reach the source cell. The number of these moves depends only on the selected source cell. The rest of the code is constant.

Copying r0 to memory
********************

Suppose we'd like to execute the following instruction: ``mov [$sp - 1], r0``. Then, the following set of Brainfuck commands shall be executed:

.. code-block:: text
    :linenos:

    <<
    [-]
    >>>
    [-]
    <
    [-<<+>>]
    >
    [-<+>]
    <

1. Go to the target cell.
2. Zero it.
3. Go to the temporary cell.
4. Zero it too.
5. Go to the source cell (r0)
6. Repeat the loop until the source cell is zero.In each loop iteration: decrease the r0, go to the target cell, increase it and go back to the source cell.
7. Go to the temporary cell.
8. Repeat the loop until the temporary cell is zero.In each loop iteration: decrease the temporary cell, go to the source cell, increase it and go back to the temporary cell.
9. Set the data pointer at r0 register.

Copying constant to memory
**************************

Copying a constant value to the memory is significantly simpler operation than the previous ones because it is free of the back up-restore overhead. The operation consists of exactly four simple steps. Consider this instruction: ``mov [$foo - 5], 10``, which will be assembled to:

.. code-block:: text
    :linenos:

    <<<<<<<
    [-]
    ++++++++++
    >>>>>>>

1. Assuming the ``$foo`` variable living in an 8th memory cell, and the current data pointer being 10, the data pointer has to be moved to the left by ``(10 - 8) + 5 = 7``.
2. The target memory cell must be zeroed.
3. Increase the memory by 10.
4. Restore the data pointer.

Control flow
++++++++++++

In Brainfuck you have only one method of controlling the execution flow: a simple loop, which is an equivalent of C's *while*; we've used that quite a lot in the previous sections. This simple loop is also the only way of mimicking conditional statements, since in Brainfuck there's no such thing as "if/else".

+--------------------------------------------------+-------------------------+--------------------------------------------------------------------------------------------------------------------------+
| Instruction                                      | Machine Code            | Description                                                                                                              |
+==================================================+=========================+==========================================================================================================================+
| ``ifnz`` <ins1, ins2, ... insN> ``repeat``       | ``[`` ... ``]``         | If value in register r0 is not zero, then execute instructions contained between ``ifnz`` and its respective ``repeat``. |
+--------------------------------------------------+-------------------------+--------------------------------------------------------------------------------------------------------------------------+

Unfortunately, we cannot control the instruction pointer, with a consequence being an inability to implement jump instructions. The code always executes from the top to the bottom, with a tiny exception for the mentioned loop.

Using variables
+++++++++++++++

Test

----

.. target-notes::

.. _`Brainfuck online interpreter`: https://www.nayuki.io/page/brainfuck-interpreter-javascript
.. _`Brainfuck Wikipedia`: https://en.wikipedia.org/wiki/Brainfuck