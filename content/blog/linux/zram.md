---
title: "Zram: RAM 'doubler' on Linux"
date: 2023-03-11T00:01:00-06:00
tags: ['linux']
---

I remember in the days of MS-DOS you could use a "RAM doubler" to
compress your memory storage and get "more" RAM, and then a bit later
on there was a joke website where you could "download" more RAM. Well
both of these are a reality in Linux (no joke), called
[Zram](https://wiki.archlinux.org/title/Zram)

On my test system, the Odroid-m1, without zram - I have 8GB of
physical RAM, and no swap:

```
$ free -m
               total        used        free      shared  buff/cache   available
Mem:            7437         170        6826           8         439        7182
Swap:              0           0           0
```

Install zram:

```
pacman -S zram-generator
cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
```

One reboot later:

```
$ free -m
               total        used        free      shared  buff/cache   available
Mem:            7437         198        7052           8         186        7160
Swap:           7436           0        7436
```

So now I have "double" the RAM, but its not filled with anything yet,
so it doesn't know how much it can compress, but obviously I cannot
use more than the physical RAM if the contents are statistically
random. But at least its _free_ RAM right? 😎

So lets fill the ram with random data and see how far it goes.

```
## Keep this running in a separate terminal
watch free -m
```

```
## In a second terminal
$ ipython

In [1]: import random

In [2]: eat_ram = []

In [3]: for gigabyte in range(17):
   ...:     eat_ram.append([random.randbytes(1024*1024) for _ in range(1000)])
   ...:     print(f"I ate {len(eat_ram)} GBs of random data")
   ...:
I ate 1 GBs of random data
I ate 2 GBs of random data
I ate 3 GBs of random data
I ate 4 GBs of random data
I ate 5 GBs of random data
I ate 6 GBs of random data
I ate 7 GBs of random data
```

At this point the machine completely freezes, and the final free
report was:

```
               total        used        free      shared  buff/cache   available
Mem:            7437        7348          36           8          52          17
Swap:           7436          35        7401
```

One hard reboot later... So lets fill up the memory with zeros (should
be infinitely compressable) and see how far it goes.

```
$ ipython
In [1]: eat_ram = []

In [2]: for gigabyte in range(17):
   ...:     eat_ram.append([bytearray(1024*1024*1000)])
   ...:     print(f"I ate {len(eat_ram)} GBs of zeros")
I ate 1 GBs of zeros
I ate 2 GBs of zeros
I ate 3 GBs of zeros
I ate 4 GBs of zeros
I ate 5 GBs of zeros
I ate 6 GBs of zeros
I ate 7 GBs of zeros
I ate 8 GBs of zeros
I ate 9 GBs of zeros
I ate 10 GBs of zeros
I ate 11 GBs of zeros
I ate 12 GBs of zeros
I ate 13 GBs of zeros
I ate 14 GBs of zeros
Killed
```

Final free report after filling the memory with all zeros, moments
before the process was killed:

```
               total        used        free      shared  buff/cache   available
Mem:            7437        7335          49           8          51          30
Swap:           7436        7258         178
```

Notably, when storing zeros it uses virtually all of the available ram
and swap space, and then it is Killed by the linux kernel OutOfMemory
(OOM) killer. The machine did _not_ crash. I suspect the earlier crash
was likely because the OOM killer didn't want to kill the process
because it thought there was another 8GB of available swap (but of
course there wasn't any, because the data was random, and couldn't be
compressed further.)

Check out the man page for `zram-generator.conf`, especially regarding
`zram-size`:

```
       O   zram-size=

           Sets the size of the zram device as a function of MemTotal,  available  as
           the ram variable.

           Arithmetic operators (^%/*-+), e, <pi>, SI suffixes, log(), int(), ceil(),
           floor(), round(), abs(), min(), max(),  and  trigonometric  functions  are
           supported.

           Defaults to min(ram / 2, 4096)
```

In the test above, this setting was set to `ram` which makes the zram
size the same size as the physical RAM. A more appropriate setting
might be `ram/2` or `ram/3` depending on how high of a compression
ratio you can expect for your workloads.

To prevent the hard crash, you can add another swap file on your solid
state disk. This swap file will only be necessary in the worst case
scenario where you need to store completely random data.

```
## Create an 8GB /swapfile
dd if=/dev/zero of=/swapfile bs=1G count=8
chmod 0600 /swapfile
mkswap /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
swapon /swapfile
```

After adding the secondary `/swapfile`, you should now have twice the
available swap space as you have physical RAM:

```
$ free -m
               total        used        free      shared  buff/cache   available
Mem:            7437         204        7037           8         195        7153
Swap:          15628           0       15628
```

Each swap has a priority value, so that the fast zram will be
preferred before using the slower disk based swap file:

```
$ cat /proc/swaps
Filename    Type            Size            Used            Priority
/swapfile   file            8388604         0               -2
/dev/zram0  partition       7615484         0               100
```

Ideally the `/swapfile` will never be needed, but in the very worst
case, it needs to be the same size as the physical RAM in order to
prevent a potential hard lock up.

There's one more setting that needs to be tweaked before we can run
the test again. Even with the second swap file, the system will still
crash when it tries to use more than the physical RAM size, and this
is because by default Linux will always prefer to use the fast
physical RAM first, and *then* use the slow swap after its full. In
the case of zram, you want it the other way: since you're using zram
you want to use *swap* as soon as possible, so that it fills up before
hitting peak memory pressure. Then if it ever does fill up compeltely,
then the secondary (disk based) swapfile will be used.

Configure the Linux kernal "swappiness" value:

```
## Configure the swappiness to 100 to more aggressively swap to zram:
cat <<EOF > /etc/sysctl.d/zram.conf
vm.swappiness=100
EOF

## Apply the value now, or reboot:
sysctl --system
```


With the extra swap buffer, here is how the random test fares:

```
# Watch the zram swap and swapfile usage separately:
## Ideally, the /swapfile usage will always say 0 because its got the lowest priority.
watch cat /proc/swaps
```

```
$ ipython

In [1]: import time

In [2]: eat_ram = []

In [3]: for gigabyte in range(17):
   ...:     eat_ram.append([bytearray(1024*1024*1000)])
   ...:     print(f"I ate {len(eat_ram)} GBs of random data")
   ...:     time.sleep(1)
   ...:
I ate 1 GBs of random data
I ate 2 GBs of random data
I ate 3 GBs of random data
I ate 4 GBs of random data
I ate 5 GBs of random data
I ate 6 GBs of random data
I ate 7 GBs of random data
I ate 8 GBs of random data
I ate 9 GBs of random data
I ate 10 GBs of random data
I ate 11 GBs of random data
I ate 12 GBs of random data
I ate 13 GBs of random data
I ate 14 GBs of random data
I ate 15 GBs of random data
I ate 16 GBs of random data
I ate 17 GBs of random data

## OK it ate all that and exhasuted all the zram,
## Lets eat some more to exhaust all of the swapfile too:
In [4]: for gigabyte in range(17,23):
   ...:     eat_ram.append([bytearray(1024*1024*1000)])
   ...:     print(f"I ate {len(eat_ram)} GBs of random data")
   ...:     time.sleep(1)
   ...:
I ate 18 GBs of random data
I ate 19 GBs of random data
I ate 20 GBs of random data
I ate 21 GBs of random data
I ate 22 GBs of random data
Killed
```

It ate all the RAM, in this order:

  * Until all the physical RAM was exhausted, at ~8G.
  * After 8G, zram started to be used, and a brief pause was observed
    between 7GB and 8GB as it starts to swap.
  * As zram is used, a bit of free physical ram was made available
    (even random data can get compressed sometimes), and so that was
    eaten too.
  * After all the zram was exhausted, then the `/swapfile` was used.
  * After almost all of the swap was used, the Kernel OOM killer
    killed python, and all the RAM was freed.

The critical  point to creating  the secondary `/swapfile` is  so that
the OOM killer functioned correctly, and killed the process before the
system froze.

## Further reading

There's a good three part series all about swap and zram from haydenjames.io:

 * [Linux Performance: Why You Should Almost Always Add Swap Space](https://haydenjames.io/linux-performance-almost-always-add-swap-space/)
 * [Linux Performance: Almost Always Add Swap. Part 2: ZRAM](https://haydenjames.io/linux-performance-almost-always-add-swap-part2-zram/)
 * [Raspberry Pi ZRAM and Kernel Parameters](https://haydenjames.io/raspberry-pi-performance-add-zram-kernel-parameters/)
