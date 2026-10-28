#!/usr/bin/env bash
# One look at the computer for the task manager (services/Tasks.qml), over about a second:
#   CPU <percent busy>
#   MEM <total kB> <available kB>
#   DISK <sectors read> <sectors written>      (running totals, whole disks)
#   NET <bytes in> <bytes out>                 (running totals, all but loopback)
#   P <pid> <ppid> <user> <cpu %> <memory kB> <name>
# The CPU figures are top's second pass (the first only counts since each process started).
ps -eo pid=,ppid= > /tmp/graphite-task-ppid.$$
top -b -n 2 -d 1 -w 512 -E k -e k 2>/dev/null | awk -v ppidfile=/tmp/graphite-task-ppid.$$ '
    BEGIN { while ((getline line < ppidfile) > 0) { split(line, part, " "); ppid[part[1]] = part[2] } }
    /^top - / { frame += 1; table = 0; next }
    frame < 2 { next }
    /^%Cpu/ { for (i = 1; i <= NF; i++) if ($i ~ /^id,?$/) idle = $(i - 1); printf "CPU %.1f\n", 100 - idle; next }
    /^ *PID / { table = 1; next }
    table && NF >= 12 {
        name = $12; for (i = 13; i <= NF; i++) name = name " " $i
        printf "P %s %s %s %s %s %s\n", $1, (ppid[$1] == "" ? 0 : ppid[$1]), $2, $9, $6, name
    }'
rm -f /tmp/graphite-task-ppid.$$
awk '/^MemTotal/ { total = $2 } /^MemAvailable/ { available = $2 } END { print "MEM", total, available }' /proc/meminfo
awk '$3 ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$/ { read += $6; written += $10 } END { print "DISK", read + 0, written + 0 }' /proc/diskstats
awk -F'[: ]+' 'NR > 2 && $2 != "lo" { down += $3; up += $11 } END { print "NET", down + 0, up + 0 }' /proc/net/dev
