---
name: active-box
description: You are running on the home server — the home-server box (Proxmox host)
metadata:
  type: reference
---

**Active box: home server** — hostname `home-server` (Proxmox host).

This is the `home-server` box. Because box-local memories only deploy to their
own machine, the presence of this note confirms the box: if you are reading it,
you are on the home server. The workstation carries its own parallel
`active-box` note instead.

Use this to resolve any box-conditional guidance directly, without inferring
the box from which repos/paths exist or running `hostname` yourself. See
[[memories-live-in-this-repo]] for the deploy model.

Static by design: if the hostname ever changes, edit this note and redeploy.
