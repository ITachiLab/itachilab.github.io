================================
Hiding files in Windows Explorer
================================

This is my private investigation on how to hide some files from being displayed in Windows's file explorer. I'll be honest - I don't see any practical usage other than malware. The goal is not to hide it completely, because that would require more advanced magic, and maybe even playing dirty tricks on kernel, it's only about not displaying certain files to typical Windows users. Oh yes, and do that without administrator privileges, and it must run from user space.

I'm going to try two methods, although only one works as expected, I've learnt that during the investigation, so it's a part of it. The first method, which didn't work, is known as *IAT hook*. The other, which eventually worked, is *inline hook*. Both methods serve the same purpose: intercept a function call, and do nasty stuff before or after the call is redirected to the original function.

The difference is that *IAT hook* replaces the address of the hooked function in the process's Import Address Table, so it basically works only on functions imported from shared libraries. But, when set up correctly, is much cleaner than the other method.

The *inline hook* alters the code of the hooked function in the memory, so when it's called it immediately jumps to the nasty code which does whatever it wants to, and redirects the call to the original function (through a so-called "trampoline"). This method is more intrusive, however, it works for any kind of function.

How to hide a file
##################

The target of the nasty code is *explorer.exe*. After a quick debugging, I've found out it relies on `NtQueryDirectoryFile <https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/nf-ntifs-ntquerydirectoryfile>`_ function to query a specified path for a list of files and directories. Now, if the result of the function is altered before it is returned to *explorer.exe*, the nasty code can completely change what will be shown to the user.

`NtQueryDirectoryFile`_ takes a decent number of parameters, but only two of them are interesting for the nasty purpose:

:FileInformationClass: the type of the requested information
:adf: fdsfs
