# workspace

The coordination hub for the **vista-cloud-dev** org: cross-repo scripts, the
clone-all manifest, and a map of where everything lives. Design docs live in
[`docs`](https://github.com/vista-cloud-dev/docs) — this repo holds the *tooling*
that ties the repos together, not the corpus.

## Bootstrap a new machine

```bash
gh repo clone vista-cloud-dev/workspace
cd workspace
./bootstrap.sh            # clones every repo in repos.txt into the parent dir
# or: VCD_DIR=/some/path ./bootstrap.sh
```

`bootstrap.sh` is idempotent and non-destructive — it clones what's missing,
checks out the right branch per repo, runs read-only toolchain checks, and never
pulls or resets an existing clone.

## Repos

| Repo | What it is |
|------|------------|
| [docs](https://github.com/vista-cloud-dev/docs) | Design/strategy corpus — dependency maps, toolchain plans, background. |
| [doc-framework](https://github.com/vista-cloud-dev/doc-framework) | Portable scaffold + validator standard behind the docs corpus. |
| [go-cli-template](https://github.com/vista-cloud-dev/go-cli-template) | Shared Go CLI scaffold. |
| [irissync](https://github.com/vista-cloud-dev/irissync) | IRIS source-sync binary — sole owner of the IRIS source boundary. |
| [vista-iris](https://github.com/vista-cloud-dev/vista-iris) | IRIS container build (VistA-on-IRIS). Active work on `feat/container-build-scaffold`. |
| workspace | This repo. |

## Files

- `repos.txt` — clone-all manifest (single source of truth for what's in the org).
- `bootstrap.sh` — new-machine setup; reads `repos.txt`.
- `git-update-repos` — fast-forward every repo in a directory; skips anything
  dirty, detached, or without an upstream.
- [`engine-lab-safety-guide.md`](engine-lab-safety-guide.md) — **read before
  launching VistA / M engines.** Resource costs, host hardening (memory caps,
  swap, OOM killer), and the safety tools below — written up after running too
  many engines hard-froze a host.
- `scripts/vista-precheck` — go/no-go capacity check **before** launching engines.
- `scripts/vista-mon` — live dashboard (mem-vs-cap, host, VM) **while** running.

## Multi-machine discipline

Development happens on more than one box (e.g. an arm64 Mac and an amd64 Linux
machine). To avoid drift: **commit + push before leaving a machine, and run
`./git-update-repos` from the org dir on arrival.** Watch that both machines are
on the same branch — `vista-iris` lives on a feature branch, not `main`.

## Arch note (arm64 ↔ amd64)

The `vista-iris` Dockerfile defaults to `IRIS_TAG=latest-cd-linux-arm64` (Apple
Silicon). On amd64 build with `--build-arg IRIS_TAG=latest-cd-linux-amd64` — it
runs native there, no emulation.
