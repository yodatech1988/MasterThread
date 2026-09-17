# Ops Fleet Status page

A snapshot of the Ops Fleet Status artifact's source, committed so the page can be rebuilt if a bad
republish loses it.

- **Live page:** https://claude.ai/artifact/AAiVG3MxK1r3yNgm8tzMmf
- **This copy is:** platform version id `1789545990-9454`, fetched 2026-09-17 by github-dc with
  Artifact `read` + `path: "index.html"`; everything between `<body>` and `</body></html>` of the
  served page. Its artifact version number and publish label were not recorded by whoever
  published it.
- **Contract for the data it shows:** `standards/sessions/fleet_status_standard.md`.

Not yet done for this page, unlike `tools/decision-queue/`: there is no test harness, and nobody
has checked this copy against the file that was originally published (the served body starts with
its own `<!doctype html>`, which the publish rules say a page file should not carry; it is kept
here as served).

To change the page, follow the procedure in `tools/decision-queue/README.md`, "Changing the page":
read live in full, diff live against this copy before editing, never `force`, omit
`capabilities`/`favicon`, read back, and update this file and the version id above in the same PR.
