# A10X_tools

Some scripts for use on A10X devices.
Only tested on iPad Pro 10,5 cellular (iPad7,4, A1709 j208ap)

## What's inside

- hello scripts
- purple mode (PMR) helpers
- ramdisk boot scripts
- misc utilities
- checkm8 and palera1n jailbreak

## Requirements

- macOS or linux host (only tested on macOS)
- checkm8-compatible device (A10X)
- libimobiledevice / irecovery / usbmuxd
- python3
- ssh client (for ramdisk access)

## Dependencies

Install the required libraries with Homebrew:

    brew install python3 libimobiledevice libirecovery libusb libplist openssl pkg-config

You'll also need Xcode Command Line Tools (`xcode-select --install`) for the compiler.

## Usage

Each script is standalone. Read the header comment in each file before running.

General flow for most of them:

1. put the device in DFU mode
2. run the script

## Tested on

- iPad Pro 10.5 (iPad7,4)

## Notes

- no warranty, use at your own risk
- things can break with iOS updates
- for research / your own devices only
- PRs welcome

## TODO

- add other repos link (gaster, palera1n, diag, SSHRD etc)
- add credits
- add dependencies 

## Disclaimer

These tools are published for research and educational purposes only. They are meant to be used on devices you own or have explicit permission to work on. Bypassing activation or modifying firmware on a device you don't own is illegal in most countries and I don't condone it. I'm not responsible for bricked devices, lost data, or any legal trouble you get yourself into. If you don't know what you're doing, don't run this.

## Credits

- [palera1n](https://github.com/palera1n/palera1n) - GPL-3.0. Binary-only copy used here.
- [SSHRD_Script](https://github.com/verygenericname/SSHRD_Script) - BSD-3-Clause. Full copy, including the prebuilt Darwin/Linux binaries and ramdisk files.
- [gaster](https://github.com/0x7ff/gaster) - checkm8 pwning utility by 0x7ff.
- [diag_script](https://github.com/orangera1n/diag_script) - for reference and some of the ramdisk/diag material.
- [diag_scripts](https://github.com/verygenericname/diag_scripts) - diag bootchain files.
- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) - device communication.
- [libirecovery](https://github.com/libimobiledevice/libirecovery) - iBoot/iBSS USB communication.
- [libusb](https://libusb.info/), [libplist](https://github.com/libimobiledevice/libplist), [OpenSSL](https://www.openssl.org/) - build and runtime dependencies.

If you're one of the authors and want a link or credit changed, open an issue.

## Licenses

Anything imported from an upstream repo keeps its original license. 

My own scripts in `scripts/` are MIT unless stated otherwise.