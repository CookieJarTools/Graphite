#!/usr/bin/env bash
# One look at the computer for the task manager (services/Tasks.qml), over about a second:
#   CPU <percent busy>
#   MEM <total kB> <available kB>
#   DISK <sectors read> <sectors written>      (running totals, whole disks)
#   NET <bytes in> <bytes out>                 (running totals, all but loopback)
#   DISKS <disk> <ms busy> ...                (running totals of each disk's active time)
#   LINK <interface> <wifi|ethernet> <Mbit/s, or 0 when it doesn't say>   (the one to the internet)
#   CORES <count> <average MHz>
#   UPTIME <seconds> <threads>
#   GPU <utilisation %> <memory used MiB> <memory MiB> <temperature °C> <name>   (NVIDIA, tab-separated)
#   P <pid> <ppid> <user> <cpu %> <memory kB> <bytes read> <bytes written> <name> <command line>
# The P lines are tab-separated (names have spaces); the bytes are running totals, known for the
# person's own processes only. The CPU figures are top's second pass (the first only counts
# since each process started). The memory is ps's (top writes "1.2g" once a number no longer
# fits its column), and for the bigger processes their share of what they use with others (PSS):
# a browser's twenty processes share most of their libraries, which counted in each would come
# to twice what it really takes.
info=/tmp/graphite-task-ps.$$
io=/tmp/graphite-task-io.$$
gpu=/tmp/graphite-task-gpu.$$
# The graphics card's figures meanwhile (NVIDIA's own tool answers in a few hundredths of a second).
command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name --format=csv,noheader,nounits > "$gpu" 2>/dev/null &
ps -eo pid=,ppid=,rss=,args= > "$info"
# Over 50 MB only: the rest share too little to matter. Reading it is the costly part of a look,
# and it changes slowly, so it's read again every ten seconds at most.
pss="${XDG_RUNTIME_DIR:-/tmp}/graphite-task-pss"
if [ ! -f "$pss" ] || [ $(( $(date +%s) - $(stat -c %Y "$pss") )) -ge 10 ]; then
    awk '$3 > 51200 { printf "/proc/%s/smaps_rollup\n", $1 }' "$info" | xargs -r grep -H '^Pss:' 2>/dev/null |
        awk -F'[/: ]+' '{ print $3, $6 }' > "$pss.new" && mv "$pss.new" "$pss"
fi
# Each process's disk use; the system's own can't be read, and are left out (grep carries on
# past them, where awk stops).
grep -H -E '^(read|write)_bytes:' /proc/[0-9]*/io 2>/dev/null | awk -F'[/: ]+' '
    $5 == "read_bytes" { read[$3] = $6 } $5 == "write_bytes" { written[$3] = $6 }
    END { for (pid in read) print pid, read[pid], written[pid] }' > "$io"
top -b -n 2 -d 1 -w 512 2>/dev/null | awk -v infofile="$info" -v iofile="$io" -v pssfile="$pss" '
    BEGIN {
        while ((getline line < infofile) > 0) {
            count = split(line, part, " ")
            ppid[part[1]] = part[2]
            rss[part[1]] = part[3]
            command = part[4]
            for (i = 5; i <= count; i++) command = command " " part[i]
            args[part[1]] = command
        }
        while ((getline line < iofile) > 0) { split(line, part, " "); read[part[1]] = part[2]; written[part[1]] = part[3] }
        while ((getline line < pssfile) > 0) { split(line, part, " "); rss[part[1]] = part[2] }
        OFS = "\t"
    }
    /^top - / { frame += 1; table = 0; next }
    frame < 2 { next }
    /^%Cpu/ { for (i = 1; i <= NF; i++) if ($i ~ /^id,?$/) idle = $(i - 1); printf "CPU %.1f\n", 100 - idle; next }
    /^ *PID / { table = 1; next }
    # Processes newer than the ps list (the top and awk of this very look among them) wait for the next.
    table && NF >= 12 && ($1 in ppid) {
        name = $12; for (i = 13; i <= NF; i++) name = name " " $i
        print "P", $1, ppid[$1] + 0, $2, $9, rss[$1] + 0, read[$1] + 0, written[$1] + 0, name, args[$1]
    }'
wait
[ -s "$gpu" ] && head -1 "$gpu" | awk -F', *' '{ printf "GPU\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5 }'
rm -f "$info" "$io" "$gpu"
awk '/^MemTotal/ { total = $2 } /^MemAvailable/ { available = $2 } END { print "MEM", total, available }' /proc/meminfo
awk '$3 ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$/ { read += $6; written += $10 } END { print "DISK", read + 0, written + 0 }' /proc/diskstats
awk -F'[: ]+' 'NR > 2 && $2 != "lo" { down += $3; up += $11 } END { print "NET", down + 0, up + 0 }' /proc/net/dev
awk 'BEGIN { printf "DISKS" } $3 ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$/ { printf " %s %s", $3, $13 } END { print "" }' /proc/diskstats
link="$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route)"
if [ -n "$link" ]; then
    speed="$(cat "/sys/class/net/$link/speed" 2>/dev/null)"
    [ "${speed:-0}" -gt 0 ] 2>/dev/null || speed=0
    echo "LINK $link $([ -d "/sys/class/net/$link/wireless" ] && echo wifi || echo ethernet) $speed"
fi
echo "CORES $(nproc) $(awk '/^cpu MHz/ { total += $4; count++ } END { printf "%.0f", count ? total / count : 0 }' /proc/cpuinfo)"
echo "UPTIME $(cut -d' ' -f1 /proc/uptime) $(cut -d' ' -f4 /proc/loadavg | cut -d/ -f2)"
