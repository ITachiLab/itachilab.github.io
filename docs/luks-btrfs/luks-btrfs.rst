######################
LUKS volume with BTRFS
######################

So, you want to encrypt some of your files, but you don't want to waste a
whole drive or a partition for that. Sometimes you just want to keep all your
dirty secrets in one place, but also keep it portable enough, so you can
easily move the data just by copying a single file.

I assume you already know what's LUKS, it's a pretty common way of encrypting
disks under Linux control. `BTRFS`_ is rarely heard of. This is a filesystem
with various features that makes it an interesting candidate for creating a
writable filesystem image for archiving purposes. It doesn't have to be
encrypted like I'm going to do in this article, if you don't need the
encryption, just omit the steps where LUKS is involved.

A few features that made me consider BTRFS:

:Compression: The files are compressed on-the-fly. The compression level and
  algorithm can be chosen when mounting the filesystem. What's interesting,
  the compression is file-wise, that means different files can be compressed
  using different methods.
:Snapshots: You can divide the disk image into subvolumes, and they behave like
  directories. Interestingly, you can create snapshots of those subvolumes,
  effectively creating a lightweight copy of the subvolume which you can modify
  without affecting the original content. BTRFS records only differences between
  the subvolume and its snapshot, so it's very space efficient.
:Resizable space: Mounted BTRFS can be easily resized (grown or shrunk).

Step by step guide
==================

First, install required tools::

  $ sudo apt install btrfs-progs cryptsetup

Now, you need to create an image file large enough to contain all your data,
let's say 128 megabytes for start, you can resize it later when necessary. ::

  $ truncate -s 128M storage.img

To create a new LUKS volume, the image file must be associate with a loop device
on which the ``cryptsetup`` command will operate::

  $ sudo losetup /dev/loop0 storage.img

With that, it's time to create a new LUKS volume, and give it a very secure
password when prompted::

  $ sudo cryptsetup -v -y luksFormat /dev/loop0

At this point, you can detach the loop device, it won't be needed anymore. The
next step is to mount the encrypted volume, and later create a new filesystem on
it. ::

  $ sudo losetup -D
  $ sudo cryptsetup open storage.img storage

The encrypted volume should be accessible at ``/dev/mapper/storage``, but you
can verify it by looking at the output of ``lsblk -p`` command. ::

  $ lsblk -p

  NAME                  MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
  /dev/loop0              7:0    0   128M  0 loop
  └─/dev/mapper/storage 254:0    0   112M  0 crypt

And now, create BTRFS on the encrypted volume::

  $ sudo mkfs.btrfs /dev/mapper/storage

The last step is to mount the filesystem, and use it like any other mounted
disk::

  $ mkdir /home/user/secret-storage
  $ sudo mount -o compress=zstd:3 /dev/mapper/storage /home/user/secret-storage
  $ sudo chown -R $(id -u):$(id -g) /home/user/secret-storage

The ``compress=zstd:3`` option will use ZSTD compression, which according to
the documentation is similar to ZLIB, but noticeably faster. The ``chown`` at
the end will make sure that the current user can write to the mounted volume.

And that's basically all you need to know. When you are done adding your
precious data to ``/home/user/secret-storage``, unmount the drive, and close
the LUKS volume. ::

  $ sudo umount /home/user/secret-storage
  $ sudo cryptsetup close storage

Additional operations
=====================

Resize
------

It's hard to predict the final size of the volume, but it's better to make it
smaller on the beginning and later expand it than the other way. This is a
three-step process which can be done even if the volume is actively mounted.
All command I'm giving assume the encrypted volume is mounted as described in
the `Step by step guide`_.

First, resize the file with the filesystem image. Let's say, we want to
resize it from the initial 128 MiB to 1 GiB, which will give us effectively
around 1008 MB of the disk space.

.. hint:: The final disk space won't be as large as the image file due to
   the boilerplate added by LUKS and BTRFS, so always make the file slightly
   larger than your actual needs.

::

   $ truncate -s 1G storage.img

The ``truncate`` command will simply append a bunch of zeros to the image
file to make it 1 GiB size. Now, the second step is to let LUKS know that the
disk changed its size::

  $ sudo cryptsetup resize storage

As a result, the device behind the encrypted volume will report it has now 1 GiB
of storage. Lastly, the third step is to grow the filesystem itself::

  $ sudo btrfs filesystem max /home/user/storage.img

The ``max`` parameter means "use all available space". You can manually tell it
how much you want the filesystem to grow, but I assumed we are greedy.

Snapshots
---------

Snapshots are a way of creating an overlay on the existing data. You can treat
them either as backups, so you change the original content, and snapshots are
your undo points; or you can add new data to snapshots, effectively creating
incremental changes to a shared starting point. Snapshots are closely related to
"subvolumes" because every snapshot is in fact a subvolume.

.. important:: Snapshots **are not** copies. BTRFS merely tracks changes between
   the snapshot and the source data, as the changes happen, and only when it is
   aware of those changes. If the source data is damaged externally (cosmic
   rays, bad sectors, binary modifications of the image file), then a snapshot
   will not help you recover the lost data.

First, create a subvolume, because snapshots can only be made from existing
subvolumes. Subvolume appears like any other directory in the file manager,
so you can create multiple subvolumes for various directories. Let's say, we
want to have a "Documents" directory in our storage, and we want to work on
those documents, while leaving ourselves a possibility of reverting changes
if our modifications happen to be bad.

Change directory to where you mounted your encrypted storage and execute::

  $ btrfs subvolume create documents

When you run ``ls`` you will see a new "documents" directory -- that's your
subvolume! Now create some document in it::

  $ echo "Hello, World!" > documents/the-world.txt

Now, let's create a snapshot to work on the document without permanently
destroying its content, and give it a try::

  $ btrfs subvolume snapshot documents documents-20260719
  $ echo "Bye, World!" > documents/the-world.txt
  $ cat documents/the-world.txt
  Bye, World!
  $ cat documents-20260719/the-world.txt
  Hello, World!

Okay, that's pretty cool, but can we snapshot a whole volume? Sure we can! It's
equally simple. And if our snapshot is supposed to be a backup, then better make
it read only with the ``-r`` flag. ::

  $ btrfs subvolume snapshot -r . backup-20260719

Now, the "backup-20260719" directory is our undo point if we remove or change
data the way we didn't meant. Another cool option is to mount the subvolume
as the main volume instead of the default root. ::

  $ sudo umount /home/user/secret-storage
  $ sudo mount -o subvol=backup-20260719 /dev/mapper/storage /home/user/secret-storage

When you enter the mounted storage, you will see only what's inside the
backup snapshot.

.. _`BTRFS`: https://btrfs.readthedocs.io/en/latest/Introduction.html

.. vim:tw=80:cc=+1:noet:ts=2:
