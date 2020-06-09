# dmvs

`dmvs` is a tool that enables you to play the NES Dr. Mario's 2-player vs. mode over the Internet.

## Installation

1. Install [fceux](http://www.fceux.com).
2. Install [luasocket](http://w3.impa.br/~diego/software/luasocket/). The linked site has binaries for Windows; on Linux:

    1. Grab a copy of the source.
    2. `make`
    3. Peek in `config`; especially check that you like the values of `INSTALL_TOP_SHARE` and `INSTALL_TOP_LIB`.
    4. `sudo make install`
    5. Make sure the directory you chose in step iii is in your `LUA_CPATH`; e.g.

            LUA_CPATH='/usr/local/lib/lua/5.0/?.so;'"$LUA_CPATH"

        should get you where you need to go with the default configuration.

3. Buy a copy of Dr. Mario, if you don't already have one.
4. Create an archival copy of Dr. Mario's ROM; e.g. Vimm's Lair has one if you don't have the hardware needed to extract it from your own cartridge.

## Usage

1. Start up fceux.
2. Load the Dr. Mario ROM.
3. Load this script with appropriate arguments (see below). If you're faster than your partner, emulation may pause until they connect; this is normal.
4. Visit the 2-player level select screen, and toggle in your favorite settings. If you are the host, hit start when both players are ready; otherwise wait impatiently for your idiot host to press the gosh darn button already, heck!

The script needs some arguments to describe how to connect with your playing partner.

* **On Windows:** Type these arguments into the "script arguments" box in fceux's lua script loading dialog box when you load `dmvs.lua`.
* **On Linux:** Type these arguments into fceux's stdin, all on a single line, then press enter. (The script *always* reads one line, so even if there are no arguments, you must press enter.)

The script can run in two modes: host or client.

### Host mode

No arguments are needed. fceux will act as a server, listening on port 7777, for incoming connections. You should make sure that your computer's port 7777 is accessible from the Internet; e.g. by adding a port-forwarding rule to your router, if appropriate. (Coming soon: bouncer mode, in case you want to host but don't know what the previous sentence means.)

You will be player 1.

### Client mode

You must give the address of a server to connect to. Your host will need to tell you an IP address or domain name that can be used to reach them.

You will be player 2.
