#!/usr/bin/env bash
# check-mod-updates.sh — poll Thunderstore for the latest version of each mod we
# run and compare it to the version currently pinned/loaded on the server, so we
# can see which mods have shipped a Valheim 1.0 (Unity 6) compatible update.
#
# Context: Valheim updated to 1.0 (build l-1.0.7, network v39, Unity 6000.0.75f1)
# on 2026-09-09. Our pinned mods pre-date that and load with compatibility errors
# (DropThat loot patch throws, Huginn map-share broken). Re-run this over the next
# few days; a mod whose "latest" version/date moves past our pin — especially one
# updated on/after the 1.0 date — is a candidate to re-pin in mods.manifest.
#
# No jq required (uses python3). Read-only: it only queries the public Thunderstore
# API and prints a report; it changes nothing on the server. Safe to re-run anytime.
#
# Usage:
#   ./check-mod-updates.sh            # human table
#   ./check-mod-updates.sh --csv      # CSV to stdout (history CSV is always appended)
#   ./check-mod-updates.sh --json     # JSON summary
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${HERE}/mods.manifest"
LOG="${HERE}/mod-update-history.csv"
VALHEIM_1_0_DATE="2026-09-09"   # mods updated on/after this are flagged "post-1.0"
API="https://thunderstore.io/api/experimental/package"

MODE="table"
case "${1:-}" in --csv) MODE="csv";; --json) MODE="json";; "") ;; *) echo "unknown arg: $1" >&2; exit 2;; esac
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

python3 - "$MODE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VALHEIM_1_0_DATE" "$API" "$LOG" "$MANIFEST" <<'PY'
import sys, os, json, urllib.request, urllib.error

mode, ts, v10_date, api, logpath, manifest = sys.argv[1:7]

# Build the mod list: [(namespace, name, pinned_version), ...]
#  - BepInExPack is installed by the lloesche image (not in the manifest); add it.
#  - the rest come from mods.manifest urls: .../package/download/<ns>/<name>/<ver>/
mods = [("denikson", "BepInExPack_Valheim", "5.4.2333")]
with open(manifest) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 6:
            continue
        name, version, url = parts[0], parts[1], parts[5]
        try:
            rest = url.split("/package/download/", 1)[1]
            ns, tname = rest.split("/")[0], rest.split("/")[1]
        except (IndexError, ValueError):
            continue
        mods.append((ns, tname, version))

def norm(v):  # "2.29.2" -> (2,29,2) for ordering
    out = []
    for part in str(v).replace("-", ".").split("."):
        out.append(int(part) if part.isdigit() else 0)
    return tuple(out)

results = []
for ns, name, pinned in mods:
    url = f"{api}/{ns}/{name}/"
    rec = {"namespace": ns, "name": name, "pinned": pinned, "latest": None,
           "date_updated": None, "deprecated": None, "status": "", "error": None}
    try:
        req = urllib.request.Request(url, headers={"accept": "application/json",
                                                   "User-Agent": "valheim-mod-check/1.0"})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.load(r)
        latest = data.get("latest", {}) or {}
        rec["latest"] = latest.get("version_number")
        rec["date_updated"] = (latest.get("date_updated") or data.get("date_updated") or "")[:10]
        rec["deprecated"] = bool(data.get("is_deprecated"))
        if rec["latest"] is None:
            rec["status"] = "no-data"
        elif norm(rec["latest"]) > norm(pinned):
            post = bool(rec["date_updated"]) and rec["date_updated"] >= v10_date
            rec["status"] = "NEWER*" if post else "NEWER"   # * = published on/after 1.0
        elif norm(rec["latest"]) == norm(pinned):
            rec["status"] = "same"
        else:
            rec["status"] = "pin-ahead"
        if rec["deprecated"]:
            rec["status"] += "+DEPRECATED"
    except urllib.error.HTTPError as e:
        rec["status"], rec["error"] = "http-error", str(e.code)
    except Exception as e:
        rec["status"], rec["error"] = "error", str(e)[:80]
    results.append(rec)

# Always append to CSV history so trends over the next days are captured.
try:
    newfile = not os.path.exists(logpath)
    with open(logpath, "a") as f:
        if newfile:
            f.write("checked_at,namespace,name,pinned,latest,date_updated,status,error\n")
        for r in results:
            f.write(",".join(str(x if x is not None else "") for x in
                    [ts, r["namespace"], r["name"], r["pinned"], r["latest"],
                     r["date_updated"], r["status"], r["error"] or ""]) + "\n")
except Exception as e:
    print(f"(warning: could not write history log: {e})", file=sys.stderr)

if mode == "json":
    print(json.dumps({"checked_at": ts, "valheim_1_0_date": v10_date, "mods": results}, indent=2))
elif mode == "csv":
    print("namespace,name,pinned,latest,date_updated,status,error")
    for r in results:
        print(",".join(str(x if x is not None else "") for x in
              [r["namespace"], r["name"], r["pinned"], r["latest"],
               r["date_updated"], r["status"], r["error"] or ""]))
else:
    print(f"Thunderstore mod-update check  —  {ts}")
    print(f"(NEWER* = a newer version was published on/after the Valheim 1.0 date {v10_date})\n")
    hdr = f"{'MOD':<22} {'RUNNING':<10} {'LATEST':<10} {'UPDATED':<11} STATUS"
    print(hdr); print("-" * len(hdr))
    for r in results:
        print(f"{r['name']:<22} {r['pinned']:<10} {r['latest'] or '-':<10} "
              f"{r['date_updated'] or '-':<11} {r['status']}"
              + (f"  ({r['error']})" if r['error'] else ""))
    newer = [r for r in results if r["status"].startswith("NEWER")]
    print()
    if newer:
        print("Action candidates (newer version available):")
        for r in newer:
            star = " [post-1.0]" if "*" in r["status"] else ""
            print(f"  - {r['namespace']}/{r['name']}: {r['pinned']} -> {r['latest']} "
                  f"(updated {r['date_updated']}){star}")
        print("\nTo adopt one: update its version + SHA-256 in mods.manifest, drop the new")
        print("DLL in ./dll/ (or let stage-mods.sh fetch it), run stage-mods.sh, then")
        print("restart the container. Client mod DLLs must match the server policy exactly.")
    else:
        print("No mod has a newer version than what we run yet. Check again in a day or two.")
    print(f"\nHistory appended to: {logpath}")
PY
