#!/bin/bash
# Compares classic/app/mactcp.h's layouts and constants with Apple's MacTCP.h
# (never copied into this repository: pass a copy you have, such as an MPW
# install's). Both are compiled for the 68000 with Retro68, and every offset,
# size and constant is printed from each and diffed.
#   classic/tests/check-mactcp-layout.sh /path/to/MacTCP.h
set -euo pipefail
apple=${1:?usage: check-mactcp-layout.sh /path/to/Apple/MacTCP.h}
here="$(cd "$(dirname "$0")/.." && pwd)"
RETRO68=${RETRO68:-$HOME/emulators/tools/retro68-build/toolchain}
cc="$RETRO68/bin/m68k-apple-macos-gcc"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/probe.c" <<'C'
#include <stddef.h>
#define O(t, f) long o_##t##_##f = offsetof(t, f);
#define S(t) long s_##t = sizeof(t);
#define K(k) long k_##k = (k);
O(TCPiopb, ioCompletion) O(TCPiopb, ioResult) O(TCPiopb, ioCRefNum) O(TCPiopb, csCode) O(TCPiopb, tcpStream)
O(TCPiopb, csParam)
O(TCPCreatePB, rcvBuff) O(TCPCreatePB, rcvBuffLen) O(TCPCreatePB, notifyProc) O(TCPCreatePB, userDataPtr)
O(TCPOpenPB, ulpTimeoutValue) O(TCPOpenPB, validityFlags) O(TCPOpenPB, commandTimeoutValue) O(TCPOpenPB, remoteHost)
O(TCPOpenPB, remotePort) O(TCPOpenPB, localHost) O(TCPOpenPB, localPort) O(TCPOpenPB, tosFlags) O(TCPOpenPB, optionCnt)
O(TCPOpenPB, options) O(TCPOpenPB, userDataPtr)
O(TCPSendPB, pushFlag) O(TCPSendPB, urgentFlag) O(TCPSendPB, wdsPtr) O(TCPSendPB, sendFree) O(TCPSendPB, sendLength)
O(TCPSendPB, userDataPtr)
O(TCPReceivePB, commandTimeoutValue) O(TCPReceivePB, markFlag) O(TCPReceivePB, rcvBuff) O(TCPReceivePB, rcvBuffLen)
O(TCPReceivePB, rdsPtr) O(TCPReceivePB, rdsLength) O(TCPReceivePB, secondTimeStamp) O(TCPReceivePB, userDataPtr)
O(TCPClosePB, validityFlags) O(TCPClosePB, userDataPtr)
O(GetAddrParamBlock, csCode) O(GetAddrParamBlock, ourAddress) O(GetAddrParamBlock, ourNetMask)
S(TCPCreatePB) S(TCPOpenPB) S(TCPSendPB) S(TCPReceivePB) S(TCPClosePB) S(wdsEntry)
K(TCPCreate) K(TCPActiveOpen) K(TCPSend) K(TCPRcv) K(TCPClose) K(TCPAbort) K(TCPRelease) K(ipctlGetAddr)
K(connectionClosing) K(connectionExists) K(connectionDoesntExist) K(connectionTerminated) K(commandTimeout)
K(openFailed) K(invalidStreamPtr) K(insufficientResources) K(ipBadAddr) K(duplicateSocket) K(invalidLength)
K(streamAlreadyOpen) K(invalidBufPtr) K(invalidRDS) K(invalidWDS) K(ipNoCnfgErr) K(ipLoadErr)
C
values() {   # $1: the header to include
    printf '#include <Types.h>\n#include "%s"\n#include "%s/probe.c"\n' "$1" "$work" > "$work/tu.c"
    "$cc" -m68000 -O0 -S -o - "$work/tu.c" 2>/dev/null |
        awk '/^[a-z]_[A-Za-z_]+:/ {name=$1} /\.long/ && name {print name, $2; name=""}'
}
values "$here/app/mactcp.h" > "$work/ours"
values "$apple" > "$work/apple"
[ -s "$work/ours" ] && [ -s "$work/apple" ] || { echo "check-mactcp-layout: a header didn't compile" >&2; exit 2; }
if diff "$work/apple" "$work/ours"; then
    echo "mactcp.h matches Apple's MacTCP.h ($(wc -l < "$work/ours") values)"
else
    echo "mactcp.h differs from Apple's (above: < Apple, > ours)" >&2; exit 1
fi
