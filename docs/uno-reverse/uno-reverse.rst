###########
Uno Reverse
###########

So it happened to me -- I've been malwared! Of course I know how and when it had 
happened, that's why you use protection, right? But sometimes you don't use it
because it's a spontaneous act, and you are confident because "it had never 
happened to me!". Well, Bill Gates was confident too. Thankfully, it was just
a computer virus so I didn't have to drug my girlfriend with antibiotics.

After I had finished bashing myself for recklessness, I switched to good old
Linux, and decided to put this worm into a jar (not Java JAR) for further 
analysis. Because I knew the time I infected my poor machine, I looked for all
created/modified files from a certain period. Thankfully, the list wasn't very
long, and after a few minutes I had my targets.

First analysis
==============

The malware added a few Windows tasks (no surprise). There were like five of 
them, but having exactly the same content for pure redundancy. One of them was
located at: ``C:\Windows\System32\Tasks\Microsoft\Windows\USB\USB-Notification``.
The task was scheduled to run a file located at: ``C:\Users\TheUser\AppData
\Roaming\DriversUpdate\Runtime_Broker.exe``.  Ah, yes! Those are always the 
"drivers" or "system" stuff. No one wants to mess with the drivers. Could be as 
well: ``Not_a_virus.exe``. So, I entered that directory, and found much more 
interesting stuff. I left those exe files for the dessert.

frp
===

Working in IT corporations taught me to avoid eye contact with others (to get
away with small talks), and to not keep password in config files. The malware
owner didn't work in corporation apparently because I've found a file named
``frpc.toml`` with... passwords! The hell is "frpc", though? It turned out to be
a configuration file for `fast reverse proxy <frp_>`_ client.

.. note::

   For those unaware, reverse proxy is a way of accessing a machine behind NAT.
   Normally, when you host a server on a machine behind NAT, no one outside the
   NATed network can connect to it, unless the router explicitly forwards ports to
   the machine. To tackle this, frequently for malicious purposes, the bad actor
   runs a program on your machine, which connects it to some server owned by the 
   bad actor. Then, it's enough to connect to that proxy server at a specific port,
   in order to forward the connection to your machine, so the proxy server simply
   bounces everything to you.

Let's dig into the configuration and see what it does.

TODO: Put TOML config here

So it runs a SOCKS server on the infected machine, interesting. The frp client 
connects to the frp server, instructs it to expose a port on it, and now if 
someone connects to the frp server at the exposed port, it is like connecting to 
the infected machine's SOCKS server. In other words: the attacker can do nasty 
stuff, and police will knock on your door.

My guts are telling me that I'm not the only victim, and the owner of the pet
worm changes passwords as frequently as his underwear. Let's see if that's true,
but it smells like it is (pun intended). Let's nmap the server and I should be
able to find other infected machines just by looking at open ports.  And, if my
"underwear theory" is correct, I can connect through victims' computers just by
reusing SOCKS and frp credentials.

TODO: Put command line evidence

The executables
===============

Let's take a look at executables shipped with the virus. Spoiler alert: 
executables in "frpc" directory are just meant for running frp client, nothing
interesting.

Before I loaded those files into my beloved x64dbg, I checked their format 
first. And guess what? They were written in C#. That reduced a week-long 
late-night debugging into a code review not taking longer than two coke-whisky 
drinks. So, `Rider`_ it is!

core.exe
--------

The "core" in filename gave me thrills. It was named "core" for a reason for 
sure! Let's load it into debugg... Sorry, force of habit! Open it in IDE, and
look at the perfectly readable code.

TODO: Put C# code here

First, that's a neat way of incorporating Telegram Bots for malicious purposes!
Second, I thought keeping passwords in a config file was stupid, well, how about
keeping encrypted data along with decrypting key in the same file? Lock your
apartment, and hang the key on a hook outside. 

.. warning:: This article is in progress.

----

.. target-notes::

.. _`frp`: https://github.com/fatedier/frp
.. _`Rider`: https://www.jetbrains.com/rider/
