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

The full set, grouped by the org m/v scope split (see `CLAUDE.md`). Mirrors
[`repos.txt`](repos.txt) — keep the two in sync.

### Coordination / docs / templates
| Repo | What it is |
|------|------------|
| workspace | This repo — the coordination hub (cross-repo scripts, manifest, map). |
| [docs](https://github.com/vista-cloud-dev/docs) | Design/strategy corpus — dependency maps, toolchain plans, background. |
| [doc-framework](https://github.com/vista-cloud-dev/doc-framework) | Portable scaffold + validator standard behind the docs corpus. |
| [go-cli-template](https://github.com/vista-cloud-dev/go-cli-template) | Shared Go CLI scaffold. |
| [v-tool-template](https://github.com/vista-cloud-dev/v-tool-template) | Scaffold for `v` (VistA) CLI tools. |

### `m-*` — engine-neutral M toolchain (runs on a bare M engine, no VistA)
| Repo | What it is |
|------|------------|
| [m-cli](https://github.com/vista-cloud-dev/m-cli) | The cross-engine M toolchain (the `m` busybox): fmt/lint/lsp/test/coverage/watch over YottaDB and IRIS. Built on m-parse. |
| [m-stdlib](https://github.com/vista-cloud-dev/m-stdlib) | Engine-neutral M standard library (`STD*`) — assertions, JSON, crypto, datetime, HTTP, etc. |
| [m-parse](https://github.com/vista-cloud-dev/m-parse) | Engine-neutral M parse substrate: tree-sitter-m via wazero (pure-Go, no CGO). |
| [m-driver-sdk](https://github.com/vista-cloud-dev/m-driver-sdk) | Shared engine-driver SDK — the verb-level Transport contract every `m-<engine>` driver implements. |
| [m-ydb](https://github.com/vista-cloud-dev/m-ydb) | The YottaDB engine driver for the m toolchain. |
| [m-iris](https://github.com/vista-cloud-dev/m-iris) | The IRIS engine driver + source-sync (formerly `irissync`) — owns the IRIS source boundary. |
| [m-dev-tools-mcp](https://github.com/vista-cloud-dev/m-dev-tools-mcp) | Thin MCP server over the reflected `m` schema. |

### `v-*` — VistA-specific (needs Kernel/FileMan/KIDS)
| Repo | What it is |
|------|------------|
| [v-stdlib](https://github.com/vista-cloud-dev/v-stdlib) | VistA Standard Library — `VSL*` routines; consumes the engine-neutral m-stdlib `STD*` base. |
| [v-pkg](https://github.com/vista-cloud-dev/v-pkg) | VistA KIDS version control (formerly `kids-vc` / `m-kids`). |
| [v-cli](https://github.com/vista-cloud-dev/v-cli) | The `v` CLI — single front-end for the VistA developer tools (`v pkg`/`db`/`config`/`rpc`/…). |
| [v-web](https://github.com/vista-cloud-dev/v-web) | VistA Web Services (`VWEB*`): inbound socket adapter driving the m-stdlib STDHTTPD framework. |
| [vpng](https://github.com/vista-cloud-dev/vpng) | `VPNG` ("vista-ping") — throwaway VSL/MSL walking skeleton; a VistA config-echo consumer. |
| [vista-iris](https://github.com/vista-cloud-dev/vista-iris) | IRIS container build (VistA-on-IRIS). Active work on `feat/container-build-scaffold`. |
| [vista-info-hub](https://github.com/vista-cloud-dev/vista-info-hub) | VistA code + documentation intelligence — one static binary, many faces. |

### vdocs (PRIVATE — clone needs org access)
| Repo | What it is |
|------|------------|
| vdocs-cli | Schema-first CLI over the vdocs VistA documentation gold corpus. |
| vdocs-tui | Faceted-discovery TUI over the vdocs gold `index.db` (read-only, offline, Bubble Tea). |
| vdocs-web | Offline, self-contained web navigator for the vdocs gold corpus. |

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
