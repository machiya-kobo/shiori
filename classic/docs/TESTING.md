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
- `shiori-sys761.hda`: a copy of the hub's System 7.6.1 disk, so its
  MacTCP can be set for slirp without touching the disk Flynn and Geomys
  share. Once, in Basilisk: Control Panels > MacTCP > More…, Obtain
  Address: Server, OK, then restart.
- `basilisk_prefs`: the hub's Basilisk II prefs, with that disk and
  `ether slirp` (user-mode networking; see Basilisk II below).

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
- `lantern`, `washi`, `kyoto`…: Machiya's invented sample pages and notes
  (`tools/sampledata.py`, the same as the README's other screenshots), for
  screenshots.
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
classic/scripts/deploy.sh basilisk --launch   # into Basilisk's Unix disk; no network (below)
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
- **Installing the DA in the System file** (what Font/DA Mover does; no
  disk here has Font/DA Mover). With Snow stopped, on a backup of
  `shiori-sys608.img`: `hcopy -m ":System Folder:System" System.bin`,
  append the DA under a free number with Rez
  (`data 'DRVR' (19, "\0x00Shiori Search", purgeable) { $$read("…/ShioriDA.flt") };`,
  `Rez install.r -a -t ZSYS -c MACS -o System.bin`), `hcopy -m` it back,
  `hattrib -t ZSYS -c MACS`. Then the Finder's Apple menu has it
  (`menu:23,172`) with Shiori not running. Restore the backup after.
- The Apple menu lists the System's DAs first; Shiori Search comes last
  (`da` opens it). On System 6 Return on a result copies its link; check it
  by pasting into Shiori's field. Close it (its close box, Mac 53, 40) and
  open it again: each entry relocates the code, so a second open must work.
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

### When the Mac bombs

A bomb ("address error", "illegal instruction") says little, and Snow's
trap history fills with the error handler's own calls at once. What
worked:

- **Bisect with alerts.** A build whose suspect path stops at each step
  with an alert naming it (`ParamText` and `NoteAlert(132, NULL)` around
  each call, compiled in for that build only). Press Return through them
  with `snow_session.py`, screenshot after each, and the last alert
  before the bomb names the step.
- **Don't use Retro68's File Manager glue** (`HOpen`, `HCreate`, `FSRead`,
  `FSWrite`, `SetEOF`, `FSClose`, `FlushVol`). It fills its parameter
  blocks only partly, leaving `ioCompletion` and the version byte as stack
  garbage, and on a Mac Plus `FSWrite` died with an address error. Call
  `PBH…Sync` and `PB…Sync` with a block you've zeroed (app/prefs.c).
- Any parameter block Shiori hands to the system is zeroed first (the
  MacTCP ones in net.c too).

### Basilisk II (System 7.6.1)

Drive it with `classic/tests/basilisk_session.py`. Its coordinates are
the Mac's, 1:1: a screenshot's less the Mac screen's origin (about 65, 59
here; the driver prints it). For example:

```sh
classic/tests/basilisk_session.py dclick:983,107 wait:4 shot:unix   # open the Unix disk
classic/tests/basilisk_session.py menu:53,30 wait:45 shot:probe     # File > Run Probe
classic/tests/basilisk_session.py menu:53,106 click:800,400 shutdown  # Quit, the Finder, Shut Down
```

Opening Shiori: `dclick:983,107` (the Unix disk), `dclick:58,218` (its
Shiori folder), `dclick:39,90` (the app), then wait 15 s. The menus' x in
Shiori: Apple 23, File 53, Edit 87, Search 138, Help 966. Menu items from
y = 26, 16 apart, with separators.

- **Always shut down from Special > Shut Down** (`shutdown`). Hard-killing
  Basilisk can corrupt the System 7 disk (Shiori's copy). The hub's recovery is in
  `~/emulators/docs/TESTING.md`.
- **Command keys sent by XTEST don't reach Basilisk** on this setup: use
  the menus.
- **Never click outside the emulator's window.** A press on WindowMaker's
  root starts a grab, and if its release never comes, every X client
  (scrot included) hangs. The driver refuses to click until it has found
  the Mac's screen, and refuses any point off it (a screenshot's
  coordinates passed as the Mac's did this once). To recover, `sudo systemctl restart sddm`, then
  `DISPLAY=:0 XAUTHORITY=~/.Xauthority xhost +local:` and
  `xset s off -dpms s noblank`.
- **Networking: use a Basilisk II built from current source.** The hub's
  `/usr/local/bin/BasiliskII` crashes on the first TCP close over slirp
  ("Caught SIGSEGV", in `tcp_close`/`tcp_reass`), and the hub's bridged
  prefs need the `sheep_net` module, which isn't built for the running
  kernel. A build of kanjitalk755/macemu's current source has a working
  slirp. Once, in your own folder (the hub's binary is left alone):

  ```sh
  git clone --depth 1 https://github.com/kanjitalk755/macemu ~/build/macemu
  cd ~/build/macemu/BasiliskII/src/Unix
  NO_CONFIGURE=1 ./autogen.sh
  ./configure --enable-sdl-video --enable-sdl-audio --with-bincue=no \
      --with-vdeplug=no --disable-jit-compiler
  make -j"$(nproc)"
  ```

  Then run it with the network on:

  ```sh
  SHIORI_BASILISK=~/build/macemu/BasiliskII/src/Unix/BasiliskII SHIORI_BASILISK_NET=1 \
      classic/scripts/deploy.sh basilisk --launch
  ```

  Without `SHIORI_BASILISK_NET=1`, `deploy.sh` starts Basilisk with no
  Ethernet (the hub's binary would crash). This build places its window
  differently: the driver calibrates either way, but a screenshot's
  coordinates are the Mac's plus a different origin (about 129, 42).
  - Without a network, MacTCP set to Server waits about a minute for an
    address on the first request, and the whole Mac waits with it (System
    7 is cooperative). The desk accessory opens MacTCP on its first
    search, not with its window, for that reason.
- **The depth is the Mac's own**: Control Panels > Monitors (Grays or
  Colors, then a depth; it applies when Monitors closes, and stays in
  Basilisk's PRAM across runs). `screen win/1024/768` offers every depth,
  so the prefs' `displaycolordepth` does nothing. Monitors opens at Mac
  (205, 147); its Grays radio is (153, 193), Colors (153, 209); the list's
  Black & White, 4, 16, 256 and Millions are at y = 190, 201, 212, 223,
  234 (x 235); its close box (152, 155). Check black and white, 16 colors,
  256 colors, 16 and 256 grays, and Millions.
- Basilisk draws grays lighter than asked (#444444 shows as #656565): the
  grays in `app/theme.c` are darker than the contrast needs for that
  reason.
- Balloon Help stays on across restarts once turned on (Help menu, Show
  Balloons). A balloon shows after the pointer rests a moment: `move:X,Y`
  then `wait:3`. A menu item's balloon: `subpeek:MENU_X,ITEM_Y` holds the
  menu open on that item for the screenshot.
- **The desk accessory's Apple events** (System 7): `ShioriAESend.bin`
  (tests/aesend.c, built with the app, never shipped) sends Shiori three
  `SHIO/read` events through the DA's own code (da/sendread.c): a page and
  a default-vault note open readers, another vault's note is refused. Its
  window shows each send's result. Put it beside Shiori with
  `python3 ~/emulators/basilisk/macbin_to_extfs.py classic/build/ShioriAESend.bin ~/emulators/unix/Shiori "AE Send"`.
  - With Shiori running, the events go straight to it.
  - With Shiori not running, it's found by its creator in a volume's
    desktop database and launched with the event. The Unix disk (extfs) has
    no desktop database: copy Shiori onto Macintosh HD with the Finder
    first (`drag:103,91,983,51`), which registers it.
  - A process that sends Apple events needs `isHighLevelEventAware` in its
    own SIZE (the tool's first build had none, and nothing arrived). The
    DA sends from whatever process it runs in: Shiori's, or System 7's DA
    Handler.
- **Snow emulates a Mac II too** (model `MacII`), which would give colour
  over Snow's working DaynaPORT, but it needs the Macintosh II Video
  Card's ROM, which the hub doesn't have.

### A real Hister over plain HTTP (direct mode)

For *Directly (HTTP)*, a throwaway Hister from the upstream image (the
version Shiori matches), on the VM's LAN address and loopback, its data on
a tmpfs, holding only the sample pages. Never the live one:

```sh
podman run -d --name shiori-classic-hister --tmpfs /hister/data:rw,size=200m,mode=1777 \
    -e HISTER__SERVER__ADDRESS=0.0.0.0:4433 -e HISTER__SERVER__BASE_URL=http://<VM's LAN address>:4440/ \
    -p <VM's LAN address>:4440:4433 -p 127.0.0.1:4440:4433 ghcr.io/asciimoo/hister:v0.20.0
tools/quickstart/seed-hister.py http://127.0.0.1:4440/
```

- With a token: add `-e HISTER__APP__ACCESS_TOKEN=…` (another name and
  port) and seed with `HISTER_TOKEN=… tools/quickstart/seed-hister.py`.
  Without it Shiori says "Hister refused this Mac (403)".
- With users: `-e HISTER__APP__USER_HANDLING=true`; `hister create-user`
  reads its password from a terminal (drive `podman exec -it` through a
  pty), and `hister update-user <name> --regen-token` prints the token.
- In Shiori: File > Preferences (`menu:54,76`), type the address (the field
  starts selected), Tab to Kura and `key:BackSpace` to clear it, click
  *Directly (HTTP)* (`click:323,48`), OK (`click:417,315`). The radio for
  the bridge is `click:166,48`.
- Real Hister replies differ from the fakes': no `Content-Length` on
  `/search` (read to the close), and a `page_key` holding escaped control
  characters and a NUL (Show More on an empty search under Pages checks
  it).
- `podman rm -f` the containers afterwards.

### Screenshots

`docs/screenshots/shiori-classic-*.png`, from the sample data (search
`lantern`, the note *Lantern festival kit*, `washi` in the desk accessory):

- **System 6** (Snow, the usual workspace): park the pointer with
  `move:509,339`, take `shot:NAME`, then
  `classic/tests/mac_shot.py snow /tmp/shiori/NAME.png OUT.png`. Snow scales
  the screen by a fraction; the tool finds the scale where every Mac pixel
  is a uniform block and reads the 512×342 screen back exactly, doubled.
  (A 2× workspace doesn't fit this display, and at 1× Snow's driver can't
  calibrate.)
- **System 7** (the networked Basilisk, millions of colors): arrange the
  windows (`drag:` by a title bar), close the Finder's windows, then
  `classic/tests/mac_shot.py basilisk IN.png OUT.png --origin X,Y --crop 0,0,1024,660`
  (the origin as `basilisk_session.py` prints it; the display cuts the
  screen's bottom rows).

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
