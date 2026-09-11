---
name: host-health
description: One-shot host performance/health report — run host/hs-health.sh to check load, mem, temp, thin-pool, uplink, VMs
metadata:
  type: reference
---

**Check the box's overall health/performance with one command:** `host/hs-health.sh`
(in the repo, `/srv/dev/repos/home-server`). Read-only. Prints a graded OK/WARN/CRIT
report and **exits 0/1/2** (nagios-style: 0 ok, 1 warn, 2 crit), so it's usable both
by a human and by a future timer/alert.

Run it as **root** (`sudo host/hs-health.sh`) or as `dev` with passwordless sudo — the
LVM-thin and VM sections need root (`lvs`, `qm`) and degrade to `n/a` without it.

**What it grades** (thresholds are env-overridable at the top of the script):
- **CPU/load** — load1 vs `nproc` (host has 8 cores), plus `%busy` from vmstat.
- **Memory** — RAM used% (from MemAvailable) + swap used%.
- **Temperature** — reads `/sys/class/thermal/thermal_zone*` directly (**no `sensors`/lm-sensors
  installed**; only the `iwlwifi` wifi-card zone is exposed — CPU-core temps aren't, absent `coretemp`).
- **Storage** — `df` per real filesystem, **plus the LVM-thin pool** `pve/data` Data%/Meta%
  (this box is LVM-thin, **not ZFS** — a full thin pool makes guests read-only, so it's the
  storage number that actually matters). Also counts `snap_*` LVM snapshots (they eat thin
  space silently — see [[valheim-server]] which snapshots before every mod change) and WARNs
  at ≥8 so stale ones get pruned.
- **Network** — `home-server-wifi.service` active? wireless iface operstate + IPv4, and an
  internet ping (`1.1.1.1`).
- **Guest VMs** — `qm list`; for each running VM it probes the guest agent with a **timeout**
  (`qm guest exec … /bin/true`), so it *detects* the agent-hang failure mode from [[valheim-server]]
  instead of hanging on it. Skip the probe with `--no-guest`.
- **Services** — any failed systemd units; count of scheduled `hs-*` timers.

**Flags:** `-q` (one-line summary — good for an alert body), `--line` (a single machine
line `LEVEL | metrics — issues`, exit 0/1/2 — what the Discord notifier consumes),
`--no-guest`, `--no-color`, `-h`.

**Discord alerts are folded into the Valheim status feed** (NOT a separate timer):
`valheim/server-status-discord.sh` calls `hs-health.sh --line --no-guest` — see
[[valheim-status-edge-notifier]]. The **daily heartbeat** post carries a host-health
snapshot as a second embed; the **3-min edge** check posts a host-health alert **only when
health crosses the CRIT boundary** (enters CRIT, or recovers out of it) — WARN is
heartbeat-only, because metrics sitting near a WARN threshold would flap every 3 min. Edge
state lives in `/var/lib/home-server/host-health.state` (`ok`/`warn`/`crit`); the heartbeat
re-baselines it. Same #valheim-server-status webhook as the other feeds.

The script itself is **not deployed by `install.sh`** — it runs in place from the repo, and
the notifier finds it at `../host/hs-health.sh` relative to its own path.
