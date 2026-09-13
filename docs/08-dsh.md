# 08 — dsh (DeepSeek Harness) on the server

`dsh` / `dsh-tui` runs as `dev`. Its `DEEPSEEK_API_KEY` follows the same secrets
rule as everything else here: it is **never** committed to this repo (see
`04-repo-and-bootstrap.md`), only its *location* is documented.

## Where the key lives

`~dev/.config/deepseek/env` — a single line `DEEPSEEK_API_KEY=...`, mode 0600,
dev-owned. Set it once:

```
install -d -m 700 ~/.config/deepseek
printf 'DEEPSEEK_API_KEY=sk-...\n' > ~/.config/deepseek/env
chmod 600 ~/.config/deepseek/env
```

## Interactive use

Use the `ds` launcher deployed by `dev-env` (`bashrc.d/10-agents.sh`). It sources
the env file before exec'ing dsh, so the key is injected at launch and never sits
in a shell profile or in git.

## Headless use (systemd)

If dsh runs headless as a unit, point the unit at the 0600 file with
`EnvironmentFile=` instead of relying on a launcher:

```ini
[Service]
User=dev
EnvironmentFile=/home/dev/.config/deepseek/env
ExecStart=/home/dev/.nvm/versions/node/v22.23.2/bin/dsh-tui
```

`EnvironmentFile` is read when the unit starts; the key stays out of the unit
file and out of git.
