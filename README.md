# dmvs

`dmvs` is a tool that enables you to play the NES Dr. Mario's 2-player vs. mode over the Internet.

## Installation

1. Install [fceux](http://www.fceux.com).
2. If you are using Linux, install [luasocket](http://w3.impa.br/~diego/software/luasocket/) (Windows' fceux comes with this bundled).

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

There are two big choices to make: host or client, and direct or via a bouncer. One player must be a host, and the other must be a client.

The other choice is a bit more complicated, and must be made by the host. If the host can make a port on their computer available to the wider Internet, then direct mode will have lower latency. If they cannot, then another alternative is to use a publically-hosted service on the Internet, and for both players to connect to that instead of directly to each other. (Instructions for setting up such a service yourself, or where to find an existing one, are in the works.)

### Host mode

You may supply the following arguments, in any order, separated by spaces. All of them are optional.

* `--bouncer HOST` Connect to the `HOST` (a domain name or IP address), and use it as a bouncer. If not specified, the script will operate in direct mode instead.

    Currently this flag is ignored: the script always runs in direct mode.

* `--port N` In direct mode, listen on this port; in bouncer mode, connect to this port of the bouncer. Defaults to 7777.
* `--require-combo` Instead of traditional vs. mode, play a modified mode where you win by clearing all viruses with a single combo. Any clear that doesn't complete the level will instead reset the level.

    Currently this flag is ignored: the script always runs in traditional vs. mode.

You will be player 1.

### Client mode

You must supply a host (a domain name or IP address in direct mode, or a connection number supplied to you by the host in bouncer mode). You may also supply the following arguments, in any order, separated by spaces, either before or after the host. All of them are optional.

* `--bouncer HOST` Connect to the `HOST` (a domain name or IP address), and use it as a bouncer.  If not specified, the script will operate in direct mode instead.

    Currently this flag is ignored: the script always runs in direct mode.

* `--port N` Connect to this port on the host (in direct mode) or bouncer (in bouncer mode). Defaults to 7777.
* `--require-combo` You may specify this, but it is ignored. Whether combos are required or not is chosen by the host.

You will be player 2.
