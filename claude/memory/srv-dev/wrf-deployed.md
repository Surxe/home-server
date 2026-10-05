---
name: wrf-deployed
description: Which WRFrontiersDB-Data commit the Site and Discount Visualizer are serving - each serves /deploy.json; `bin/wrf-deployed` in the Orchestrator compares both with Data main
metadata:
  type: reference
---

**What data is live?** Run `/srv/dev/repos/WRFrontiersDB-Orchestrator/bin/wrf-deployed`
(`--json` for scripts). For the Site (wrf-db.info) and the Discount Visualizer it prints the
Data commit + version each serves, how many commits behind Data `main`, when/how it was
built (run URL), and whether the Site's pipeline state file is that same deploy. Exit 0 only if
both serve `main`.

- **Source of truth:** each frontend's live `/deploy.json`
  (`curl -s https://wrf-db.info/deploy.json | jq`), written at build time by
  WRFrontiersDB-Data's shared `record-deploy` action (fields: `tools/wrfdb_data/deploy_record.py`
  there). It covers every deploy, including Site pushes and hand-run Visualizer deploys.
- **Pipeline copy (Site only):** `WRFrontiersDB-Orchestrator/data/site_deploy_state.json`,
  written by SITE-DEPLOY from the run's `deploy-record` artifact, for the Discord bot
  ([[wrf-discord-bot]]). A Site push or hand deploy doesn't update it. The Visualizer has
  no state file; its live `/deploy.json` is the only record.
- **Before 2026-10:** deploys had no record; a 404 on `/deploy.json` means the frontend
  hasn't been deployed since the records were added.
