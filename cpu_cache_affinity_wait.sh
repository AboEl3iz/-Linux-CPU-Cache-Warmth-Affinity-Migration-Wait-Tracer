#!/usr/bin/env bash
#
# cpu_cache_affinity_wait.sh - Production CLI Wrapper & Help Interface for CPU Affinity & Cache Wait Tool
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT_SCRIPT="${SCRIPT_DIR}/cpu_cache_affinity_wait.bt"

PID_FILTER=""
COMM_FILTER=""
INTERVAL=0
UNITS="us"

show_help() {
    cat << 'EOF'
NAME
       cpu_cache_affinity_wait - Trace CPU affinity wait and cache-warmth migration latency

SYNOPSIS
       cpu_cache_affinity_wait.sh [-p PID] [-c COMM] [-i INTERVAL] [-u us|ms] [-h]

DESCRIPTION
       cpu_cache_affinity_wait measures and categorizes the duration tasks spend in
       the RUNNABLE state while target CPUs in the system are IDLE, but migration was
       prevented by kernel load balancing logic.

       Migration rejections are categorized into two primary kernel causes:
         1. Cache Warmth (task_hot()): The task executed recently on its current CPU.
            Migrating it would incur CPU L1/L2/L3 cache line invalidated penalties.
            Controlled by sysctl kernel.sched_migration_cost_ns (or sysctl_sched_migration_cost).
         2. Hard CPU Affinity: The task is restricted by affinity masks (p->cpus_ptr)
            from executing on the target idle CPU.

OPTIONS
       -p PID
              Filter tracing output for a specific Process ID.

       -c COMM
              Filter tracing output for a specific command name (process comm).

       -i INTERVAL
              Print interval statistics every INTERVAL seconds.

       -u UNITS
              Time unit for histogram output: 'us' (microseconds, default) or 'ms' (milliseconds).

       -h, --help
              Display this manual page and exit.

KERNEL DECISION FLOW
       [ Task Runnable on CPU A ] ──> [ Load Balancer (CPU B is Idle) ]
                                                │
                                      can_migrate_task(p, env)
                                                │
                          ┌─────────────────────┴─────────────────────┐
                          ▼                                           ▼
             [ CPU B in p->cpus_ptr? ]                      [ task_hot(p, env)? ]
                   │ (No)                                         │ (Yes: delta < sched_migration_cost)
                   ▼                                              ▼
           CPU AFFINITY REJECTION                        CACHE WARMTH REJECTION
       (Task waits on CPU A for CPU A)             (Task waits on CPU A for cache to cool)

EXAMPLES
       Trace entire system with final summary on Ctrl-C:
              sudo ./cpu_cache_affinity_wait.sh

       Filter for process PID 12345:
              sudo ./cpu_cache_affinity_wait.sh -p 12345

       Filter for process comm 'postgres':
              sudo ./cpu_cache_affinity_wait.sh -c postgres

       Print periodic report every 5 seconds:
              sudo ./cpu_cache_affinity_wait.sh -i 5

SEE ALSO
       bpftrace(8), sysctl(8), sched(7), taskset(1)

AUTHOR
       Senior Kernel & eBPF Performance Engineering Team
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--pid)
            PID_FILTER="$2"
            shift 2
            ;;
        -c|--comm)
            COMM_FILTER="$2"
            shift 2
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -u|--units)
            UNITS="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option $1" >&2
            echo "Run '$0 -h' for usage information." >&2
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (or with sudo)." >&2
   exit 1
fi

if [[ ! -f "$BT_SCRIPT" ]]; then
    echo "Error: bpftrace file $BT_SCRIPT not found!" >&2
    exit 1
fi

echo "=================================================================="
echo " Starting CPU Cache-Warmth & Affinity Wait Tracer"
echo " Configuration:"
[[ -n "$PID_FILTER" ]]  && echo "   - PID Filter   : $PID_FILTER"
[[ -n "$COMM_FILTER" ]] && echo "   - COMM Filter  : $COMM_FILTER"
[[ "$INTERVAL" -gt 0 ]] && echo "   - Interval     : ${INTERVAL}s"
echo "   - Latency Unit : $UNITS"
echo "=================================================================="

# Execute bpftrace
exec bpftrace "$BT_SCRIPT"
