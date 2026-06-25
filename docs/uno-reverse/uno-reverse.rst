###########
Uno Reverse
###########

So it happened to me -- I've been malwared! Of course I know how and when it had 
happened, that's why you use protection, right? But sometimes you don't use it
because it's a spontaneous act, and you are confident because "it had never 
happened to me!". Well, Bill Gates was confident too. Thankfully, it was just
a computer virus so I didn't have to drug my girlfriend with antibiotics, lol.

After I had finished bashing myself for recklessness, I switched to good old
Linux, and decided to put this worm into a jar (not Java JAR) for further 
analysis. Because I knew the time I infected my poor machine, I looked for all
created/modified files from a certain period. Thankfully, the list wasn't very
long, and after a few minutes I had my targets.

First analysis
==============

The malware added a few Windows tasks (of course it did). There were like five 
of them, but having exactly the same content -- pure redundancy. One of them was
located at: ``C:\Windows\System32\Tasks\Microsoft\Windows\USB\USB-Notification``.
The task was scheduled to run a file located at: ``C:\Users\TheUser\AppData\Roaming\DriversUpdate\Runtime_Broker.exe``.
Ah, yes! Those are always the "drivers" or "system" stuff. No one wants to mess
with drivers, right? Could be as well: ``Not_a_virus.exe``. So, I entered that
directory, and found much more interesting stuff. I left those exe files for the
dessert.

frp
===

Working in IT corporations taught me to avoid eye contact with others (to get
away with small talks), and to not keep password in config files. The malware 
owner didn't work in corporation apparently because I've found a file named 
``frpc.toml`` with... passwords! The hell is "frpc", though? It turned out to
be a configuration file for `fast reverse proxy <frp_>`_ client.

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

Oh, so it runs a SOCKS server on the infected machine, interesting. The frp 
client connects to the frp server, instructs it to expose a port on it, and now 
if someone connects to the frp server at the exposed port, it is like 
connecting to the infected machine's SOCKS server. In other words: the 
attacker can do nasty shit, and police will knock on your door.

But look, we have passwords and shit here! If I'm not mistaken, I'm not the only
victim, and the owner of the pet worm changes passwords as frequently as his 
underwear. Let's see if that's true, but it smells like it is (put intended). 
How? Just nmap this moron, duh! I should be able to locate other infected 
machines just by finding open ports. And, if my "underwear theory" is correct,
I can connect through victims' computers just by reusing SOCKS and frp 
credentials.

Told ya -- stinks like meth head's breath. I could stop there, and be a parasite
on someone else's hard work; after all it's convenient to have "safe gateways".
On the other hand, fuck this guy, I still hold the grudge for what he has done
to me. Why not pawn his little business or make his life harder?

Possible punishments
--------------------

The frp server configuration is hardcoded on victims' machines, that means Mr. 
Smelly Pants has virtually no means of changing those. So, if the server is down
or attacked in a way that makes it unusable, the attacker can't just switch to 
another server and take his bots with him. Moreover, the existing worm spreading
the config will be useless.

I can open a fake SOCKS on my machine, and sniff what the attacker is up to. 
That could give me some valuable information, or even more credentials. To
not put my IP's good name on risk, I can tunnel those connections further 
through any of the already infected machines. Don't look at me like that, they 
are infected anyway!

Share the config publicly. I bet lots of people would find his hard work very
useful.

The executables
===============

Before I start doing anything, let's give a closer look to those few executables
living along. Spoiler alert: executables in "frpc" directory are just meant for
running frp client, boring.

Btw, before I loaded those files into my beloved x64dbg, I checked their format
first. Guess what? They were written in C#, lol. That reduced a week-long 
late-night debugging into two-coke-whisky-drinks-long code review. Paraphrasing 
the popular meme: "I'm very lucky he's so fucking stupid". So, `Rider`_ it is!

core.exe
--------

The "core" in filename gave me thrills. It was named "core" for a reason for 
sure! Let's load it into debugg... Sorry, force of habit! Open it in IDE, and
look at the perfectly readable code.

First, that's a neat way of incorporating Telegram Bots for malicious purposes!
Second, I thought keeping passwords in a config file was stupid, well, how about
keeping encrypted data along with decrypting key in the same file? Lock your
apartment, and hang the key on a hook outside. 

.. warning:: This article is in progress.

----

.. target-notes::

.. _`frp`: https://github.com/fatedier/frp
.. _`Rider`: https://www.jetbrains.com/rider/
