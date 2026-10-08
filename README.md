# Linux CPU Cache-Warmth & Affinity Migration Wait Tracer

[![CI & Packaging](https://github.com/AboEl3iz/-Linux-CPU-Cache-Warmth-Affinity-Migration-Wait-Tracer/actions/workflows/ci.yml/badge.svg)](https://github.com/AboEl3iz/-Linux-CPU-Cache-Warmth-Affinity-Migration-Wait-Tracer/actions/workflows/ci.yml)
[![eBPF Engine](https://img.shields.io/badge/eBPF-bpftrace-blue.svg)](https://github.com/bpftrace/bpftrace)
[![Kernel Version](https://img.shields.io/badge/Kernel-5.4%2B%20%7C%206.x-brightgreen.svg)](https://kernel.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade eBPF dynamic tracing tool built on `bpftrace` to diagnose and quantify scheduling delays caused by kernel load balancer decision constraints.

Specifically, **`cpu_cache_affinity_wait`** measures and categorizes the exact duration tasks spend waiting in the `RUNNABLE` state on busy CPUs while other system CPUs are completely `IDLE`, but migration was explicitly rejected by kernel scheduler logic.

---

##  Problem Overview

In modern multi-core, SMP, and NUMA Linux architectures, CPU cores often sit idle while tasks wait in runqueues (`RUNNABLE` state). System administrators and performance engineers frequently ask:

> *Why isn't the kernel load balancer immediately migrating my runnable process to an available idle CPU core?*

The Linux kernel Completely Fair Scheduler (CFS) load balancer (`can_migrate_task`) rejects task migration to idle cores for two main reasons:

1. **Cache Warmth Rejection (`task_hot()`)**: The task ran on its current CPU very recently. Migrating it would invalidate CPU L1/L2/L3 cache lines, resulting in a net performance loss.
2. **Hard CPU Affinity Restriction**: The task's affinity mask (`p->cpus_ptr`) restricts it from running on the available idle CPU core.

This toolhooks into the kernel's scheduler decision path using eBPF `fexit` and `tracepoint` probes to calculate the exact latency impact of these restrictions.

---

##  Kernel Decision Logic & Workflow

```
[ Task Runnable on CPU A ] ──> [ Load Balancer (CPU B is Idle) ]
                                         │
                               can_migrate_task(p, env)
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   ▼                                           ▼
      [ CPU B in p->cpus_ptr? ]                      [ task_hot(p, env)? ]
            │ (No)                                         │ (Yes: delta < migration_cost)
            ▼                                              ▼
    CPU AFFINITY REJECTION                        CACHE WARMTH REJECTION
(Task waits on CPU A for CPU A)             (Task waits on CPU A for cache to cool)
```

---

##  Features

- **Zero-Overhead Kernel Instrumentation**: Uses eBPF `fexit:can_migrate_task` and `tracepoint:sched:sched_switch` for low overhead in production environments.
- **Dual Cause Categorization**: Automatically separates delays caused by L1/L2/L3 cache protection (`task_hot`) from hard mask constraints (`cpus_ptr`).
- **Logarithmic Latency Histograms**: Provides distribution charts of runnable wait latency in microseconds.
- **Per-Process Breakdown**: Identifies exact process command names (`comm`) suffering from scheduling rejections.
- **Production Shell Wrapper**: Includes CLI options for easy execution, help manual, and packaged installation.

---

##  Prerequisites

- **OS**: Linux Kernel `5.4+` (with BTF enabled at `/sys/kernel/btf/vmlinux`) or Kernel headers installed.
- **Tooling**: `bpftrace` ($\ge$ 0.12.0) and standard `bash` ($\ge$ 4.0).
- **Permissions**: Root (`sudo`) privileges or `CAP_BPF` / `CAP_PERFMON` / `CAP_SYS_ADMIN` capabilities.

---

##  Installation & Packaging

### Option 1: Debian / Ubuntu Package (`.deb`)

Download the latest `.deb` from [GitHub Releases](https://github.com/AboEl3iz/-Linux-CPU-Cache-Warmth-Affinity-Migration-Wait-Tracer/releases) or build locally:

```bash
sudo dpkg -i cpu-cache-affinity-wait_1.0.0_all.deb
```

### Option 2: RPM Package (`.rpm`) - RHEL / Fedora / Rocky Linux

```bash
sudo rpm -ivh cpu-cache-affinity-wait-1.0.0-1.noarch.rpm
```

### Option 3: Standalone Tarball (`.tar.gz`)

```bash
tar -xzf cpu-cache-affinity-wait-1.0.0-linux-x86_64.tar.gz
cd cpu-cache-affinity-wait-1.0.0-linux-x86_64
sudo ./install.sh
```

### Option 4: Build from Source using `Makefile`

```bash
git clone https://github.com/AboEl3iz/-Linux-CPU-Cache-Warmth-Affinity-Migration-Wait-Tracer.git
cd -Linux-CPU-Cache-Warmth-Affinity-Migration-Wait-Tracer

# Build all packages (.deb, .rpm, .tar.gz) into dist/
make package

# Install directly to /usr/local/bin
sudo make install
```

---

##  Usage

Once installed, you can invoke the tracer using either `cpu_cache_affinity_wait` or `cpu_cache_affinity_wait.sh`:

```bash
sudo cpu_cache_affinity_wait [OPTIONS]
```

### CLI Command Options

| Option | Long Flag | Description |
| :--- | :--- | :--- |
| `-p PID` | `--pid PID` | Filter tracing output for a specific Process ID |
| `-c COMM` | `--comm COMM` | Filter tracing output for a process command name |
| `-i SEC` | `--interval SEC` | Output interval statistics every `SEC` seconds |
| `-u UNIT` | `--units UNIT` | Latency units: `us` (microseconds, default) or `ms` |
| `-h` | `--help` | Display manual page and usage details |

### Usage Examples

1. **System-wide Tracing** (Collect stats until `Ctrl-C`):
   ```bash
   sudo cpu_cache_affinity_wait
   ```

2. **Filter for specific application** (e.g., PostgreSQL or Nginx):
   ```bash
   sudo cpu_cache_affinity_wait -c postgres
   ```

3. **Trace single Process ID**:
   ```bash
   sudo cpu_cache_affinity_wait -p 12345
   ```

---

##  Sample Output Report

```text
===================================================================
              CPU MIGRATION WAIT PERFORMANCE REPORT               
===================================================================

--- Total Migration Rejections to Idle CPUs by Process ---
Cache Warmth Rejections (@denied_cache_warm_count):
@[redis-server]: 412
@[postgres]: 189

CPU Affinity Rejections (@denied_affinity_count):
@[nginx]: 1024
@[ffmpeg]: 350

--- Cache-Warmth Runnable Wait Latency Histogram (microseconds) ---
@cache_warm_wait_latency_us: 
[2, 4)                45 |@@@@@@                                  |
[4, 8)               182 |@@@@@@@@@@@@@@@@@@@@@@@@@               |
[8, 16)              310 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[16, 32)              64 |@@@@@@@@                                |

--- CPU Affinity Runnable Wait Latency Histogram (microseconds) ---
@affinity_wait_latency_us: 
[16, 32)              12 |@@@                                     |
[32, 64)              98 |@@@@@@@@@@@@@@@@@@@                     |
[64, 128)            512 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[128, 256)           240 |@@@@@@@@@@@@@@@@@@                      |
```

---

##  Tuning & Actionable Remediation

If `cpu_cache_affinity_wait` highlights significant latency spikes:

1. **High Cache Warmth Wait**:
   - Check current migration cost setting:
     ```bash
     sysctl kernel.sched_migration_cost_ns
     ```
   - If workload tasks lose cache quickly or run small burst items, lower migration cost (e.g. from `500000` ns to `100000` ns):
     ```bash
     sudo sysctl -w kernel.sched_migration_cost_ns=100000
     ```

2. **High CPU Affinity Wait**:
   - Evaluate process pinning settings (`taskset`, `numactl`, systemd `CPUAffinity`).
   - Relax CPU affinity masks if cores are sitting idle unnecessarily while restricted threads wait on saturated CPUs.

---

##  CI / CD & Automated Packaging

This repository includes a fully automated GitHub Actions pipeline (`.github/workflows/ci.yml`) that:
- Runs static analysis and shell script linting via `ShellCheck` & `bash -n`.
- Builds Debian (`.deb`), RPM (`.rpm`), and Tarball (`.tar.gz`) packages on every push/PR.
- Automatically publishes release assets to GitHub Releases upon git tag pushes (`v*`).

---

##  License

Distributed under the [MIT License](LICENSE).
EOF
