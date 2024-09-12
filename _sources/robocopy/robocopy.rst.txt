Robocopy
========

I'm pretty sure that only a small group of Windows's users is aware of existence of a tool named **robocopy**. I bet it's better known among administrators, but an ordinary user would benefit from knowing this tool too. Personally, I discovered this utility after I needed to transfer over 30 GB of data shared through SMB while being connected to an unstable network. I'm sure there are tools that could do that, but why download one more unnecessary software when you can use a built-in one.

All information needed to start using robocopy can be found in the command line manual after executing: ``robocopy /?`` . I'm not going to describe every part of it, I will focus only on the most common use-cases.

Backup
------

The basic functionality of robocopy is an ability to copy only those files which aren't in the target directory or those which were modified in the source directory. This feature makes this tool perfect for typical backups on an external drive. This can be done with the following command::

    robocopy C:\Users\Foo\Documents Z:\Documents /Z /E

The syntax is self explanatory: copy all files from the first path to the second path. It's worth noting that robocopy works on directories, it compares content of both of them and does its magic. However, copying single files is also possible.

The two parameters at the end need a quick explanation:

:/Z: Enables restarting interrupted copying, perfect for large files.
:/E: Enables recursive copying.

In order to delete files from the target directory which were deleted from the source directory, the ``/PURGE`` switch is the answer. ``/PURGE /E /Z`` can be replaced with: ``/MIR /Z``.

:/PURGE: Delete destination files/directories that no longer exist in source.
:/MIR: Mirror a directory tree (equivalent to ``/E`` plus ``/PURGE``).

To omit unwanted directories, use option: ``/XD``, wildcards are acceptable. ::

    robocopy C:\Users\Foo\Data Z:\Data /E /XD unwanted_dir1 unwanted_dir2

In order to exclude files, there's another switch: ``/XF``, and it works analogously.

Copying a single file
---------------------

Copying single files is possible too, robocopy isn't only for directories. ::

    robocopy C:\Users\Foo\ Z:\ legal_windows.iso /Z /J

:/J: Copy using unbuffered I/O (recommended for large files).

The above command is the one that I used for copying data through an unstable link. If the internet connection drops, the command can be simply executed again when the connection is back, and robocopy will continue the transfer as if nothing had happened.
