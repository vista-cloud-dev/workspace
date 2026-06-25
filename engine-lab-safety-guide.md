# Engine Lab Safety Guide — running VistA / M engines without freezing your host

This guide memorializes a real incident and its fix: launching too many VistA / M
engine containers (plus a VirtualBox CPRS client VM) **hard-froze the host**,
forcing a power-cycle. It documents the measured resource costs, the root cause,
the host hardening that prevents recurrence, and the two safety tools that ship in
[`scripts/`](scripts/).

If you are setting up a new machine for this org, read this **before** you start
launching engines. It is the missing piece that `bootstrap.sh` does not cover:
host capacity planning.

---

## TL;DR

1. **Only run the engines you need.** CPRS work needs just `vehu` (YDB, ~110 MiB).
   IRIS is 8–40× heavier. Don't leave `foia*` / `vista-iris` / `m-test-iris`
   running idle.
2. **Cap every container** so a runaway is OOM-killed in its own cgroup, not on the
   host: `docker run/update --memory=Ng --memory-swap=Ng`.
3. **Give the host headroom**: ≥ 8 GiB swap and a userspace OOM killer
   (`earlyoom` or `systemd-oomd`).
4. **Check before you launch**: `scripts/vista-precheck <names>` → GO / RISKY / NO-GO.
5. **Watch while running**: `scripts/vista-mon` (live) or `vista-mon --once`.

---

## What happened (the incident)

A Windows VM running CPRS hit a runaway ("infinite") process. The whole host then
froze and required a hard reboot — taking down every running container with it
(seen afterward as several containers all `Exited (255)` at the same instant).

Investigation showed the host had **no safety nets**:

| Gap | Consequence |
|-----|-------------|
| No container had a memory limit (`HostConfig.Memory = 0`) | A runaway can consume unbounded RAM. |
| Only 2 GiB swap on a 27 GiB host running VMs | No cushion; RAM fills → hard thrash → lock. |
| No userspace OOM killer (`systemd-oomd` inactive, no `earlyoom`) | Nothing kills the runaway before the kernel deadlocks. |
| (Likely compounding) VirtualBox 7.2.6 KVM backend on a very new kernel | A pathological guest can hang the host hypervisor path. |

At **idle** all engines + the VM summed to only ~7 GiB, so steady state alone did
not exhaust 27 GiB — the freeze came from a **runaway against a host with no
limits and no OOM backstop**. The fix makes a runaway *contained and survivable*
instead of host-fatal.

---

## Measured resource footprint (idle)

Measured on a 27 GiB / 16-core host via `docker stats` + `/proc/meminfo`.

| Engine | What it is | Idle resident | Budget under load |
|--------|-----------|--------------:|------------------:|
| **YottaDB** (`vehu`) | VistA-on-YDB | **~110 MiB** | ~2 GiB cap is ample |
| **IRIS community** (`m-test-iris`) | bare IRIS | **~850 MiB** | 2–4 GiB |
| **VistA-on-IRIS** (`foia-t12`) | full VistA on IRIS | **~850 MiB** + page cache | 4 GiB |
| **IRIS-VistA** (`vista-iris`) | IRIS-VistA | ~850 MiB+ | 4 GiB |
| **Win10 VM** | VirtualBox CPRS client | **5 GiB hard** | reserved in full at launch |

Notes:
- **IRIS costs ~8–40× more RAM than YDB.** Prefer YDB for routine work.
- `docker stats` MEM understates IRIS's reserved shared memory and ignores page
  cache; the table's "budget under load" numbers are the safe figures to plan with.
- The IRIS images run with `globals=0, gmheap=0, routines=0` in `iris.cpf`
  (**auto-allocation** — IRIS sizes buffers from host RAM). Pinning explicit
  buffer sizes is an advanced option if you want deterministic reservations.

---

## Host hardening (apply once per machine)

### 1. Cap every engine container
A capped container that runs away triggers a **cgroup OOM kill inside the
container** — the host is untouched. `docker update` applies live (no restart):

```bash
docker update --memory=2g --memory-swap=2g vehu
docker update --memory=2g --memory-swap=2g m-test-engine
docker update --memory=4g --memory-swap=4g foia-t12
docker update --memory=4g --memory-swap=4g vista-iris
docker update --memory=4g --memory-swap=4g m-test-iris
```

For anything you `docker run` fresh, bake the cap in:
`--memory=4g --memory-swap=4g --cpus=4`.
(Setting `--memory-swap` equal to `--memory` denies the container host swap, so it
cannot thrash host swap.)

### 2. Grow swap to ≥ 8 GiB
A cushion so spikes page out instead of hard-locking:

```bash
sudo swapoff /swapfile && sudo fallocate -l 8G /swapfile \
  && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
```
(`/etc/fstab` already referencing `/swapfile` makes it persist across reboots.)

### 3. Install a userspace OOM killer
Kills the largest process when RAM/swap runs low — **before** the kernel locks
(the default OOM killer reacts too late under thrash):

```bash
sudo apt install -y earlyoom && sudo systemctl enable --now earlyoom
```

### 4. (Optional) Cap the VM's CPU
Stops a runaway guest from pegging all host cores:

```bash
VBoxManage controlvm <vm-name> cpuexecutioncap 90   # live; or modifyvm when off
```

---

## The tools (`scripts/`)

Both are plain bash, no dependencies beyond `docker` / `VBoxManage`. Put them on
your `PATH` (e.g. symlink into `~/scripts/bin/`) or run from `scripts/`. Override
the VirtualBox guest name with `VISTA_VM_NAME=<name>`.

### `vista-precheck` — go/no-go BEFORE launching
Sums the RAM budget of what's running plus what you intend to launch, compares it
against host RAM with a safety margin, and flags missing safety nets.

```bash
vista-precheck                 # report current state
vista-precheck vehu            # "can I also start vehu?"
vista-precheck foia-t12 vm     # ...foia-t12 AND the Win10 VM?
```
Exit code: `0` GO, `2` RISKY (fits total RAM but low free now), `1` NO-GO
(would exceed host RAM) — so it can gate a launch script. Edit the `BUDGET` table
at the top of the script to add engines or tune figures.

### `vista-mon` — live dashboard WHILE running
Host RAM/swap/load + each engine's **mem-vs-its-cap %** (OOM proximity) + the VM,
in one screen. Flags any engine ≥ 80% of its cap.

```bash
vista-mon            # refresh every 3s (Ctrl-C to quit)
vista-mon 1          # 1s interval
vista-mon --once     # single snapshot — scriptable / loggable
```

Built-in alternatives: `docker stats` (raw firehose; with caps set, its MEM%
column = OOM proximity) and `btop` (host-wide; spot a runaway eating cores/RAM).

---

## Operating discipline

- Run `vista-precheck <names>` before bringing up engines.
- Keep `vista-mon` open during heavy sessions (e.g. CPRS hammering `vehu`, or any
  multi-engine run).
- Stop engines you're not using — especially the IRIS-class ones.
- The number that matters is **MEM% vs cap**: an engine nearing 100% OOM-kills
  *itself* (contained); `earlyoom` is the host-level backstop beneath that.

---

## Engine access reminder (org rule)

Reaching a live engine to **run M code** still goes through the driver stack only
(`m test` / `m vista exec` / `mdriver.Client`) — see the org `CLAUDE.md` and
[`docs/memory/engine-access-through-driver-stack.md`](https://github.com/vista-cloud-dev/docs).
The scripts here only do **container lifecycle / host monitoring** (`docker
stats`, `docker inspect`, `docker update`, `VBoxManage`) — never `docker exec ...
mumps` — so they comply with the transport monopoly.
