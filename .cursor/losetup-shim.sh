#!/usr/bin/env bash
# losetup shim for AnotterKiosk image builds inside a Cloud Agent VM.
#
# Why this exists:
#   The Cloud Agent VM runs on a shared host kernel whose loop driver was
#   built with max_part=0 (see /sys/module/loop/parameters/max_part). With
#   max_part=0 the kernel never scans a loop device for partitions, so
#   `losetup -P` cannot create the /dev/loopNpM partition nodes that the
#   build scripts (build_x86.sh / build_raspberry_pi.sh) expect. On GitHub
#   Actions runners the loop driver allows partition scanning, so the scripts
#   work there unchanged.
#
# What this does:
#   This wrapper is installed to /usr/local/sbin/losetup, which precedes
#   /usr/sbin in sudo's secure_path, so `sudo losetup ...` resolves here. It
#   forwards every argument to the real losetup and, whenever partition
#   scanning is requested (-P), uses `partx` (BLKPG ioctl, which works
#   regardless of max_part) to create the partition nodes. On detach it
#   removes those nodes first. This keeps the repository's build scripts
#   completely unmodified.

REAL=/usr/sbin/losetup

is_detach=0
want_partscan=0
explicit_dev=""
for a in "$@"; do
  case "$a" in
    -D|--detach-all|-d|--detach) is_detach=1 ;;
    -P|--partscan) want_partscan=1 ;;
    /dev/loop*) explicit_dev="$a" ;;
  esac
done

if [ "$is_detach" -eq 1 ]; then
  if [ -n "$explicit_dev" ]; then
    partx -d "$explicit_dev" >/dev/null 2>&1 || true
  else
    # -D detaches every loop device; strip partition nodes from all of them.
    for d in $("$REAL" -O NAME -n -l 2>/dev/null); do
      partx -d "$d" >/dev/null 2>&1 || true
    done
  fi
  exec "$REAL" "$@"
fi

# Attach path: run the real losetup and preserve its stdout (e.g. the device
# path emitted by --show), which callers capture in a variable.
out="$("$REAL" "$@")"
rc=$?
[ -n "$out" ] && printf '%s\n' "$out"

if [ "$rc" -eq 0 ] && [ "$want_partscan" -eq 1 ]; then
  dev="$explicit_dev"
  if [ -z "$dev" ]; then
    dev="$(printf '%s\n' "$out" | grep -m1 '^/dev/loop' || true)"
  fi
  if [ -n "$dev" ]; then
    partx -a "$dev" >/dev/null 2>&1 || partx -u "$dev" >/dev/null 2>&1 || true
  fi
fi
exit "$rc"
