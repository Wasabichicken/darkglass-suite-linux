# Unofficial Darkglass Suite for Linux

At the time of writing, Darkglass Electronics does not distribute a
Linux version of their Darkglass Suite. This repository hosts a script
that downloads the Windows version of the Suite and patches, rebuilds,
and repackages it as a Linux-runnable AppImage.

This repository is **unaffiliated with Darkglass Electronics!** Any
use of this unofficial version is done **ABSOLUTELY ON YOUR OWN
RISK**, with **NO GUARANTEES** that it won't brick your Darkglass
device. Proceed with the utmost caution!

## But it's been tested?

Only with Darkglass Anagram, no other Darkglass devices.

## What the script does

In order, the script:

1. Downloads the newest version of the Darkglass Suite installer for
   Windows that this script currently has patches for (from a mirror,
   not from Darkglass directly - see below) and unpacks it,
2. Double-checks that the downloaded version really is supported,
   otherwise aborts. If this happens, please file an issue.
3. Patches the C and JavaScript source (see [patches/](patches/)),
4. Builds Darkglass' C module for serial communication,
5. Repackages the Electron app as a runnable AppImage.

### Why a mirror, and not Darkglass directly?

To the best of my knowledge, Darkglass's own download endpoint only
ever serves whichever version is currently latest. Fetching from it
directly meant this script became unusable the moment Darkglass ships
a version newer than whatever had last been patched here.

Instead, `build.sh` fetches a specific, known-supported version by name
from a small personal mirror that archives installers as new versions
are released, so they're still around even after Darkglass moves on.
See [mirror/](mirror/) if you'd like to run your own copy of it.

## Build requirements

* `curl`,
* `7z`,
* `npx`, `npm`, `node`,
* `gcc`/`g++`/`make`
* `python3`,
* `patch`, `file`, `grep`, `sed`, `dos2unix`.
* FUSE

To install these on Debian:

```sh
$ sudo apt install curl 7zip npm nodejs build-essential python3 patch file grep sed dos2unix fuse3
```

## Build instructions

Download this repository in your preferred manner, either via `git` or
as a ZIP file. Then, from the (unpacked) project directory:

```sh
$ ./build.sh
```

By default, this fetches the newest supported version from the mirror
(see above). If you'd rather use a specific installer you already have
- an older version, or if the mirror is unreachable - point the script
at it directly with `--installer`:

```sh
$ ./build.sh --installer "cache/Darkglass Suite-6.8.0-rc10-x64.exe"
```

This skips the download entirely; the version is still determined from
the installer's filename and validated against `patches/` as usual, so
this can't be used to sneak past the version check. An output path can
still be given as an extra, final argument.

## Runtime requirements

For Darkglass Anagram, the Darkglass Suite communicates with the
device using two device files, `/dev/ttyACM<n>` and
`/dev/hidraw<n>`. Depending on your distribution, read- and write access
to these might be restricted.

On Debian, `/dev/ttyACM<n>` is owned by the group `dialout`, so adding
your user to that group, logging out, and logging in again fixes that:

```sh
$ sudo usermod -aG dialout $USER
```

Also on Debian, `/dev/hidraw<n>` is owned by root, so a `udev` rule is
required. Write the following to
e.g. `/etc/udev/rules.d/99-darkglass-anagram.rules`:

```sh
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2fa6", ATTRS{idProduct}=="2500", GROUP="dialout", MODE="0660"
```

## Running the Suite

From the directory where you ran the build script:

```sh
$ ./Darkglass-Suite-<version>-x86_64.AppImage
```

(Substitute `<version>` as appropriate)

## What's been changed from the official version?

1. The auto-updater has been disabled. While Windows- and Mac versions
   of the Darkglass Suite can just download updated versions directly
   from Darkglass, these unofficial builds must be continuously
   patched and rebuilt every time Darkglass releases a new
   version. Since there's no way to do that automatically, the
   auto-updater was (in its current form) non-functioning.
2. The original serial code was using a non-functioning `ioctl()`
   call. This call is restricted on modern Linux systems, was failing
   silently, and has been replaced with a short (100ms) `poll()`
   timeout to detect hangups instead.

## What's supported?

Technically; nothing. As previously stated, using these builds are
done **ENTIRELY ON YOUR OWN RISK**, and **NOBODY BUT YOU** are liable
if your Darkglass device breaks as a consequence of using this
software.

That said, the build script has been found to work without known
issues for several versions of the Darkglass Suite:

* Firmware upgrade,
* Marketplace block download,
* Preset loading/modification

... All appear to work just fine.

## Can I contribute?

Yes, just file an issue and we'll talk. In particular, it would be
interesting to make this work for Darkglass devices other than the
Anagram.
