# compose-launcher

One shared source for the `run.sh` and `run.ps1` launchers that are currently copied into three projects:

- [site](https://github.com/Nate314/site) (PR #70)
- [java-rest-example](https://github.com/Nate314/java-rest-example) (PR #5)
- [EZPoll](https://github.com/Nate314/EZPoll) (PR #47)

**Status: the generic launcher is implemented here, and not adopted anywhere yet.** `run.sh` and `run.ps1` in this repository read a per-project `run.conf` and reproduce what the copied scripts do. The three projects above still carry their own copies: adopting this one is a later step, tracked per project from [#1](https://github.com/Nate314/compose-launcher/issues/1).

## What is in this repository

| Path | Purpose |
| --- | --- |
| `run.sh` | The launcher for Git Bash, macOS and Linux. The same file for every project. |
| `run.ps1` | The launcher for PowerShell, with the same behavior. The same file for every project. |
| `examples/<project>/run.conf` | The config that reproduces each of the three projects' current launcher. |
| `tests/` | Launcher tests for both shells and the throwaway stack they start. |

## What the launchers do

A project ships `run.sh`, `run.ps1` and its own `run.conf` next to its `docker-compose.yml`. Both scripts behave the same:

- Create a git-ignored `.env` on first run if none exists. Existing `.env` files are never overwritten: only the port variables are added or adjusted.
- Choose free host ports. Each port starts at its default (8080 for the main web port) and scans upward. A port is busy if something accepts a TCP connection on 127.0.0.1, so native processes count as well as containers. Ports picked earlier in the same run are skipped too.
- Skip re-validating ports while the project's stack is already running, and re-validate a stale `.env` when it is not, so several stacks can be started back to back without colliding.
- Print the URLs it picked, and pass any arguments straight to `docker compose` (`./run.sh down`, `./run.sh logs -f`). With no arguments it runs `docker compose up --build -d`.

Only the lines of the port variables in `.env` are touched: every other byte, including CRLF line endings, is kept. A stored port value that is not a positive number is replaced by the default.

`docker compose` has no pre-run hook, so a bare `docker compose up` cannot generate the `.env`. That is why a wrapper script exists. Bare `docker compose up --build` keeps working with the 8080 defaults for a single project.

## Config format

`run.conf` is the only file that differs between projects. It is plain text, one entry per line, words separated by spaces. Blank lines and lines starting with `#` are ignored, and anything else is an error.

| Line | Meaning |
| --- | --- |
| `port NAME DEFAULT` | A host port variable written to `.env`, and the port to start scanning from. The order of the lines is the order in which ports are picked. |
| `url TEXT` | A line printed after `up`. Every `{NAME}` is replaced by the chosen port. The text is printed as written, so labels can be aligned with spaces. |
| `note KEY\|KEY TEXT` | Prints TEXT after the ports were chosen when `.env` sets any of the keys. EZPoll uses it to warn about explicit `ALLOWED_ORIGINS` or `PUBLIC_SOCKET_URL` values. |

The config for java-rest-example ([examples/java-rest-example/run.conf](examples/java-rest-example/run.conf)):

```
port APP_PORT 8080
port PMA_PORT 8082
port MYSQL_PORT 3306

url App:        http://localhost:{APP_PORT}
url Swagger UI: http://localhost:{APP_PORT}/swagger-ui.html
url phpMyAdmin: http://localhost:{PMA_PORT}
url MySQL:      127.0.0.1:{MYSQL_PORT}
```

The port variable names must match the ones the project's `docker-compose.yml` interpolates (for example `"${APP_PORT:-8080}:8080"`).

## Testing the launchers

`tests/test.sh` checks `run.sh` and `tests/test.ps1` checks `run.ps1`. Both copy the launcher and the throwaway stack in `tests/fixture` (one `busybox` container publishing two ports) into a temp folder, run the same five scenarios against real `docker compose`, and remove everything they started:

1. A native process holding the default port is skipped, and the second port skips the one just picked.
2. A rerun while the stack is running leaves `.env` and the container alone.
3. A second and a third stack started back to back get different ports without editing anything.
4. A stale `.env` is re-validated once the stack is stopped.
5. An existing `.env` with custom values keeps every byte, and only the missing port is appended.

```
bash tests/test.sh                                                     # Git Bash, macOS, Linux
pwsh -NoProfile -File tests/test.ps1                                   # PowerShell 7
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\test.ps1 # Windows PowerShell 5.1
```

The exit code is 0 when every check passes, 1 when a check fails, and 2 when the tests could not start. They need Docker and ports 18080 to 18087 and 18095 free, so run one of them at a time. `tests/test.sh` also needs `python3`, `python` or PowerShell for the native listener: that is a requirement of the test, not of the launcher.

Passing on Windows 11 in Git Bash, PowerShell 7 and Windows PowerShell 5.1. Not run on macOS or Linux yet, see [#3](https://github.com/Nate314/compose-launcher/issues/3).

In a PowerShell session use `run.ps1`. `bash ./run.sh` there resolves to `C:\WINDOWS\system32\bash.exe`, which is WSL and not Git Bash.

## Why one shared source

The copied scripts are 70 to 91 lines each, six copies in total, and they differ only in configuration:

| Project | Port variables (default) |
| --- | --- |
| site | `SITE_PORT` (8080) |
| java-rest-example | `APP_PORT` (8080), `PMA_PORT` (8082), `MYSQL_PORT` (3306) |
| EZPoll | `CLIENT_PORT` (8080), `SOCKET_PORT` (3000), `API_PORT` (5000), `MYSQL_PORT` (3307), `PHPMYADMIN_PORT` (8083) |

EZPoll's browser-visible origins (`PUBLIC_SOCKET_URL`, `ALLOWED_ORIGINS`) are derived from those ports by nested interpolation in its `docker-compose.yml`, so the launcher does not need to know about them.

Fixing a bug in the copies means editing six files in three repositories, and the two implementations had already drifted slightly: the bash copy only probes with a connect, the PowerShell copy also tries to bind.

## Differences from the copied scripts

- Port detection is the same in both shells: connect only. Bash cannot bind a port without an extra host tool, so `run.ps1` dropped its bind attempt instead.
- `run.ps1` passes every argument through. The copies declare a `param()` block, which makes PowerShell read `-d` as its own `-Debug` switch, so `.\run.ps1 up --build -d` dropped the `-d` and ran `docker compose up --build`.
- `run.ps1` no longer rewrites the whole `.env` with LF line endings when it changes a port, and `run.sh` no longer does so in Git Bash.
- Both scripts fall back to the default for the same stored values (empty, not a number, or starting with 0).

## Constraints

- Each project must still work when cloned on its own and offline. No submodule that breaks a plain `git clone`, and no `curl | bash` at run time.
- Both shells stay supported (Git Bash/macOS/Linux and native Windows PowerShell).
- No new host dependency: Docker only.

## Design

1. **Vendor, do not fetch.** Not implemented yet, see [#4](https://github.com/Nate314/compose-launcher/issues/4). Keep the single implementation here and copy it into each project with `git subtree` or a small sync script, plus a check that the vendored copies are byte-identical to this repository. Downloaders get plain files.
2. **Data-driven.** Implemented. One generic launcher plus a small per-project config (port variables and defaults, the labels used when printing URLs), so the vendored copies do not differ between projects.
3. **Tests as a compose service.** Not implemented yet, see [#2](https://github.com/Nate314/compose-launcher/issues/2). Add an `e2e` service to each project's `docker-compose.yml` behind a `profiles` entry (official Playwright image, `network_mode: host`, ports taken from `.env`). Then `docker compose --profile e2e run --rm e2e` runs the Playwright suite in either shell, and `./run.sh test` is a one-line pass-through. This replaces the long `docker run` commands in the READMEs. This part has not been tried yet.
4. **Launcher tests.** Implemented in `tests/` and run on Windows only so far, see [#3](https://github.com/Nate314/compose-launcher/issues/3). Automate the checks that were done by hand: native process on the default port, stale `.env`, a second and third stack starting back to back, rerun while running.

## Decisions taken as defaults

These were open questions. The choices below are defaults that can be overruled in review.

- **Two implementations, bash and PowerShell, with identical behavior.** Running the launcher inside a container would leave a single implementation, but it would need a wrapper per shell anyway and could not probe the host's ports without host networking.
- **A sync script instead of `git subtree`**, so the projects receive plain files and no history rewrite. The script and the drift check are tracked in [#4](https://github.com/Nate314/compose-launcher/issues/4).

## Open questions

- Should first run generate random secrets into `.env` instead of shipping dev-only defaults? (Database passwords only apply when the data volume is first created, so this needs care.)
- Should this repository be public? The vendored copies are already public inside the three projects.

## Issues

- [#1](https://github.com/Nate314/compose-launcher/issues/1) Design and roll-out plan
- [#2](https://github.com/Nate314/compose-launcher/issues/2) Run the Playwright suites through a compose `e2e` service
- [#3](https://github.com/Nate314/compose-launcher/issues/3) Test the launchers on macOS, Linux and Windows PowerShell 5.1
- [#4](https://github.com/Nate314/compose-launcher/issues/4) Keep the vendored copies from drifting
