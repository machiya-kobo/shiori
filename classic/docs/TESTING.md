# Testing Shiori for Classic Macintosh

Three places run the app: Snow (System 6.0.8 on an emulated Mac Plus, the
primary target), Basilisk II (System 7.6.1, for grays and color), and a
real Mac Plus. Host tests cover the portable core and the bridge. Nothing
here touches a real Hister or Kura: the emulators talk to the **fake
house**, which is the real bridge in front of fake services.

## Host tests (any machine)

```sh
node --test scripts/classic.test.mjs   # the bridge's tests, and the core's
make -C classic/tests test             # the core alone (cc, C89)
```

`classic/tests/check-mactcp-layout.sh /path/to/MacTCP.h` checks every
offset, size and constant in our own `app/mactcp.h` against Apple's header
(not in this repository; the claude VM has a copy in Geomys's checkout).
Run it after touching `mactcp.h`.

## The emulator machine

The emulators run on a Linux test machine with the classic Mac **emulator
hub** at `~/emulators`: Snow, Basilisk II, the ROMs, a System 6.0.8 disk
with MacTCP and the DaynaPORT driver (`disks/system6.img`), a System 7.6.1
disk (`disks/system7.hda`), the Retro68 toolchain
(`tools/retro68-build/toolchain`) and the XTEST automation library
(`scripts/snow_automation.py`). The hub's own guide is
`~/emulators/docs/` (SNOW.md, TESTING.md, SNOW-GUI-AUTOMATION.md). Flynn
and Geomys use the same hub. For the agents this is the claude VM.

### Setting up (once)

```sh
classic/scripts/setup-emulators.sh        # --force to start over
```

This creates `classic/diskimages/` (gitignored), with:

- `shiori-sys608.img`: a copy of the hub's System 6 disk with every other
  project's folders removed, so the Finder's list shows Shiori on its
  second row without scrolling. The hub's disk is never written.
- `shiori.snoww`: its Snow workspace (a Mac Plus ROM, the disk on SCSI 0,
  DaynaPORT Ethernet on SCSI 3, 4 MB).
- `basilisk_prefs`: the hub's Basilisk II prefs with `ether slirp`
  (user-mode networking; see Basilisk II below).

Then put the default settings in `classic/local.env` (gitignored; the
build reads it):

```sh
SHIORI_DEFAULT_HISTER=http://<this machine's LAN address>:8070/
SHIORI_DEFAULT_KURA=http://<this machine's LAN address>:8071/
SHIORI_DEFAULT_TOKEN=mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
```

The token is the fake house's (43 K's), not a real one.

### The fake house

```sh
classic/scripts/fake-house.sh start     # admits this machine's /24; --allow NETWORK to choose
classic/scripts/fake-house.sh status | log | stop
```

(It runs `classic/tests/fake_house.py`, and tracks it by PID file.)

This runs the real bridge (`classic/bridge/bridge.py`) on ports 8070
(Hister) and 8071 (Kura), with:

- `haiku/fake-services.py` behind it, on loopback (a fake Hister and a fake
  Kura that log every credential and shout `LEAK` when one goes astray);
- a fake hister-login that knows the one room token.

The bridge swaps the Mac's room token for fake Hister's token, as the real
one does. Search words:

- `heavy` (Hister): 20 rows shaped like a real reply, about 16 KB.
- `many` (Hister 45 pages; Kura 45 notes).
- Kura's error words: `redirect` (a 302), `slow` (12 s), `big` (300 KB,
  over the Mac's cap) and `huge` (600 KB, over the bridge's: a 413).

Snow's NAT connects from this machine's own LAN address. Basilisk II
connects from its own address when bridged, or from this machine's when
on slirp. **Never `pkill -f` or `pgrep -f` a pattern** here: it matches
your own shell's command line, and over SSH it kills the session.
`fake-house.sh` uses a PID file for that reason.

### Build and deploy

```sh
classic/scripts/build.sh                      # classic/build/Shiori.{bin,dsk}
classic/scripts/deploy.sh snow --launch       # onto Snow's disk, then start Snow
classic/scripts/deploy.sh basilisk --launch 8 # into Basilisk's shared folder; 1, 2, 4 or 8 bits
```

### Snow (System 6.0.8)

Drive it with `classic/tests/snow_session.py`. For example:

```sh
classic/tests/snow_session.py open-app shot:launched probe shot:probe
classic/tests/snow_session.py type:heavy return wait:25 shot:search   # a search
classic/tests/snow_session.py tab return shot:opened                   # into the list, open the first
classic/tests/snow_session.py da shot:da
```

The steps are listed in the script. Screenshots land in `/tmp/shiori/`.
What we learned setting it up:

- **Snow needs `SDL_AUDIODRIVER=dummy` on the VM.** Without it, the
  emulated Mac never draws a frame (a uniform dark grey screen, and Snow's
  own screenshot is blank too): the host's audio device stalls emulation.
  `deploy.sh` sets it.
- **Never write Snow's disk while Snow runs** (it is memory-mapped). Stop
  Snow by PID, never `pkill -f` (it matches the caller's own command
  line). `deploy.sh` does this.
- **The app lives at the disk's top level.** A folder made by hfsutils
  has no window position, and the Finder opened it off-screen.
- The Mac Plus keyboard has no Escape or Control key: ⌘-. is Escape. Snow
  maps Right Alt to Command.
- The Apple menu lists the System's DAs first; Shiori Search comes last.
- Screenshots: `scrot` only, never ImageMagick's `import`: it grabs the
  pointer and Snow's mouse stays broken until restart.
- The XTEST library has no keysym named ".": ⌘-. is `cmd_key("period")`
  (the `stop` step).
- **Snow's keyboard has no arrow keys** (it's the original M0110), and
  ⌘ with a digit never reaches the Mac. In Snow, use Tab to move into the
  list and the Search menu for the pills. The Mac Plus's own M0110A has
  arrows, and ⌘1–⌘4 work there.
- Menu items sit 16 pixels apart from y = 28 (item 1); the menus' x in
  Shiori: Apple 23, File 54, Edit 87, Search 136. Coordinates near the
  window's right edge are a few pixels off after calibration: aim inside.

### Basilisk II (System 7.6.1)

Drive it with `classic/tests/basilisk_session.py` (Mac coordinates, 1:1).
For example:

```sh
classic/tests/basilisk_session.py dclick:983,107 wait:4 shot:unix   # open the Unix disk
classic/tests/basilisk_session.py menu:53,30 wait:45 shot:probe     # File > Run Probe
classic/tests/basilisk_session.py menu:53,62 shutdown               # Quit, then Shut Down
```

- **Always shut down from Special > Shut Down** (`shutdown`). Hard-killing
  Basilisk corrupts the shared System 7 disk. The hub's recovery is in
  `~/emulators/docs/TESTING.md`.
- **Command keys sent by XTEST don't reach Basilisk** on this setup: use
  the menus.
- **Never click outside the emulator's window.** A press on WindowMaker's
  root starts a grab, and if its release never comes, every X client
  (scrot included) hangs. The driver refuses to click until it has found
  the Mac's screen. To recover, `sudo systemctl restart sddm`, then
  `DISPLAY=:0 XAUTHORITY=~/.Xauthority xhost +local:` and
  `xset s off -dpms s noblank`.
- **Networking:**
  - The hub's prefs bridge Basilisk onto the LAN through the `sheep_net`
    kernel module, which must be built for the running kernel. After a
    kernel update it's gone, and `modprobe sheep_net` fails.
  - Shiori's prefs use `ether slirp` instead (no module). But the shared
    System 7 disk's TCP/IP is configured for the bridged LAN, so on slirp
    the Mac can't reach the fake house yet (connections time out,
    -23016).
  - Until `sheep_net` is rebuilt, System 7 runs are UI-only.
- The color depth comes from `deploy.sh basilisk --launch DEPTH`. Check
  every screen at 1 bit, 4 bits (16 grays) and 8 bits (256 colors).

### The Mac Plus

The real Mac Plus reaches the LAN through a BlueSCSI (DaynaPORT over
Wi-Fi) at a fixed address, and takes builds on the BlueSCSI's SD card:
copy `classic/build/Shiori.dsk`, or the release's `.dsk`, onto the card.
The owner tests it. Live services are reached only through the deployed
bridge, and only for reads.

## Measurements (Snow, Mac Plus, 4 MB)

| Reply | Bytes | Rows | Connect | Transfer | Parse |
|---|---|---|---|---|---|
| Hister `heavy` | 16,101 | 20 | 0.3 s | 5.8 s | 0.9 s |
| Kura `many` | 6,200 | 20 | 0.2 s | 2.6 s | 0.5 s |

Phase 2, after the switch to the non-blocking fetch (parse now decodes
every field of every row):

| Reply | Bytes | Rows | Connect | Transfer | Reads | Parse |
|---|---|---|---|---|---|---|
| Hister `heavy` | 16,101 | 20 | 0.5 s | 5.8 s | 30 | 1.5 s |
| Kura `many` | 6,200 | 20 | 0.2 s | 2.8 s | 11 | 0.9 s |

- Free memory after both: 3.5 MB (single Finder, the whole machine).
- Parsing a page of results is fine. Transfer is the cost: the reply
  comes in segments of about 540 bytes, one every 0.19 s, about 2.8 KB/s
  through Snow's emulated DaynaPORT. Larger receive buffers (16 KB) and
  several reads per event-loop pass (Geomys's fix) didn't change it, so
  the limit is the emulated network, not the app. The real Plus on a
  BlueSCSI will tell.
- So the app asks for 10 rows a page (the 512×342 list shows about 8).
  If the real Plus is as slow, the next step is compression in the bridge
  (JSON shrinks about 5x; an inflater is small on a 68000).
- A `fields=` filter on Kura's `/api/note` (it sends the body twice) is
  worth proposing if notes prove slow.
