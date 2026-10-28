#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! "${1:-}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: %s <Cleo process ID>\nReads five samples from an already running process; never launches an app.\n' "$0" >&2
  exit 2
fi
cleo_pid="$1"
printf 'PID %s — five samples, two seconds apart.\n' "$cleo_pid"
printf 'CPU is ps average CPU usage; RSS is resident memory, not total memory footprint.\n'
printf '%-9s %10s %12s %12s\n' 'Sample' 'CPU (%)' 'RSS (MiB)' 'Elapsed'
for sample in 1 2 3 4 5; do
  if ! metrics="$(/bin/ps -p "$cleo_pid" -o %cpu=,rss=,etime=)" || [[ -z "$metrics" ]]; then
    printf 'Process %s is no longer available.\n' "$cleo_pid" >&2
    exit 1
  fi
  printf '%s\n' "$metrics" | /usr/bin/awk -v sample="$sample" '{printf "%-9s %10s %12.1f %12s\n", sample, $1, $2 / 1024, $3}'
  if [[ "$sample" != 5 ]]; then sleep 2; fi
done

