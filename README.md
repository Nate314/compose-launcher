# compose-launcher

One shared source for the `run.sh` and `run.ps1` launchers that are currently copied into three projects:

- [site](https://github.com/Nate314/site) (PR #70)
- [java-rest-example](https://github.com/Nate314/java-rest-example) (PR #5)
- [EZPoll](https://github.com/Nate314/EZPoll) (PR #47)

**Status: design only.** Nothing is implemented in this repository yet. The working scripts live in the three projects above, and the tracking issue is [#1](https://github.com/Nate314/compose-launcher/issues/1).

## What the launchers do today

Every project ships a bash script (`run.sh`, for Git Bash, macOS and Linux) and a PowerShell script (`run.ps1`) with the same behavior:

- Create a git-ignored `.env` on first run if none exists. Existing `.env` files are never overwritten: only the port variables are added or adjusted.
- Choose free host ports. Each port starts at its default (8080 for the main web port) and scans upward. A port is busy if something accepts a TCP connection on 127.0.0.1, so native processes count as well as containers (`run.ps1` also tries to bind).
- Skip re-validating ports while the project's stack is already running, and re-validate a stale `.env` when it is not, so several stacks can be started back to back without colliding.
- Print the URLs it picked, and pass any arguments straight to `docker compose` (`./run.sh down`, `./run.sh logs -f`). With no arguments it runs `docker compose up --build -d`.

`docker compose` has no pre-run hook, so a bare `docker compose up` cannot generate the `.env`. That is why a wrapper script exists. Bare `docker compose up --build` keeps working with the 8080 defaults for a single project.

## Why one shared source

The scripts are 70 to 91 lines each, six copies in total, and they differ only in configuration:

| Project | Port variables (default) |
| --- | --- |
| site | `SITE_PORT` (8080) |
| java-rest-example | `APP_PORT` (8080), `PMA_PORT` (8082), `MYSQL_PORT` (3306) |
| EZPoll | `CLIENT_PORT` (8080), `SOCKET_PORT` (3000), `API_PORT` (5000), `MYSQL_PORT` (3307), `PHPMYADMIN_PORT` (8083) |

EZPoll's browser-visible origins (`PUBLIC_SOCKET_URL`, `ALLOWED_ORIGINS`) are derived from those ports by nested interpolation in its `docker-compose.yml`, so the launcher does not need to know about them.

Fixing a bug today means editing six files in three repositories, and the two implementations have already drifted slightly (the bash version only probes with a connect, the PowerShell version also tries to bind).

## Constraints

- Each project must still work when cloned on its own and offline. No submodule that breaks a plain `git clone`, and no `curl | bash` at run time.
- Both shells stay supported (Git Bash/macOS/Linux and native Windows PowerShell).
- No new host dependency: Docker only.

## Proposed design (not yet decided)

1. **Vendor, do not fetch.** Keep the single implementation here and copy it into each project with `git subtree` or a small sync script, plus a check that the vendored copies are byte-identical to this repository. Downloaders get plain files.
2. **Data-driven.** One generic launcher plus a small per-project config (port variables and defaults, the labels used when printing URLs), so the vendored copies do not differ between projects.
3. **Tests as a compose service.** Add an `e2e` service to each project's `docker-compose.yml` behind a `profiles` entry (official Playwright image, `network_mode: host`, ports taken from `.env`). Then `docker compose --profile e2e run --rm e2e` runs the Playwright suite in either shell, and `./run.sh test` is a one-line pass-through. This replaces the long `docker run` commands in the READMEs. This part has not been tried yet.
4. **Launcher tests.** Automate the checks that were done by hand: native process on the default port, stale `.env`, a second and third stack starting back to back, rerun while running.

## Open questions

- `git subtree` or a sync script? Where should the drift check run?
- Keep two implementations (bash and PowerShell) or run the launcher inside a container so there is only one?
- Should first run generate random secrets into `.env` instead of shipping dev-only defaults? (Database passwords only apply when the data volume is first created, so this needs care.)
- Should this repository be public? The vendored copies are already public inside the three projects.

## Issues

- [#1](https://github.com/Nate314/compose-launcher/issues/1) Design and roll-out plan
- [#2](https://github.com/Nate314/compose-launcher/issues/2) Run the Playwright suites through a compose `e2e` service
- [#3](https://github.com/Nate314/compose-launcher/issues/3) Test the launchers on macOS, Linux and Windows PowerShell 5.1
- [#4](https://github.com/Nate314/compose-launcher/issues/4) Keep the vendored copies from drifting
