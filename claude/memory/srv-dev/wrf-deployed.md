---
name: wrf-deployed
description: Which WRFrontiersDB-Data commit the Site and Discount Visualizer are serving - each serves /deploy.json; `bin/wrf-deployed` in the Orchestrator compares both with Data main
metadata:
  type: reference
---

**What data is live?** Run `/srv/dev/repos/WRFrontiersDB-Orchestrator/bin/wrf-deployed`
(`--json` for scripts). For the Site (wrf-db.info) and the Discount Visualizer it prints the
Data commit + version each serves, how many commits behind Data `main`, when/how it was
built (run URL), and whether the pipeline's state file is that same deploy. Exit 0 only if
both serve `main`.

- **Source of truth:** each frontend's live `/deploy.json`
  (`curl -s https://wrf-db.info/deploy.json | jq`), written at build time by
  WRFrontiersDB-Data's shared `record-deploy` action (fields: `tools/wrfdb_data/deploy_record.py`
  there). It covers every deploy, including Site pushes and hand-run Visualizer deploys.
- **Pipeline copies:** `WRFrontiersDB-Orchestrator/data/site_deploy_state.json` (SITE-DEPLOY)
  and `visualizer_deploy_state.json` (discount run), downloaded from the run's
  `deploy-record` artifact. The Discord bot reads the Site one ([[wrf-discord-bot]]).
- **Before 2026-10:** deploys had no record; a 404 on `/deploy.json` means the frontend
  hasn't been deployed since the records were added.
