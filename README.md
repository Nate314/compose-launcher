# compose-launcher

A small launcher for Docker Compose projects: it picks free host ports, writes them to `.env`, runs `docker compose`, and prints the URLs. It exists so that several projects that all default to port 8080 can run side by side without editing anything.

The launcher lives only in this repository. A project includes it as a **git submodule** and keeps just two tiny stub scripts and its own `run.conf`. Projects using it:

- [site](https://github.com/Nate314/site)
- [java-rest-example](https://github.com/Nate314/java-rest-example)
- [EZPoll](https://github.com/Nate314/EZPoll)

## What is in this repository

| Path | Purpose |
| --- | --- |
| `run.sh` | The launcher for Git Bash, macOS and Linux. |
| `run.ps1` | The launcher for PowerShell, with the same behavior. |
| `stub/run.sh`, `stub/run.ps1` | The stubs a project copies to its root once. They fetch the submodule if it is missing and hand over to the launcher. |
| `tests/` | Launcher tests for both shells and the throwaway stack they start. |

## What the launcher does

It works on the current folder, which must hold the project's `docker-compose.yml` and `run.conf`. Both scripts behave the same:

- Create a git-ignored `.env` on first run if none exists. Existing `.env` files are never overwritten: only the port variables are added or adjusted.
- Choose free host ports. Each port starts at its default (8080 for the main web port) and scans upward. A port is busy if something accepts a TCP connection on 127.0.0.1, so native processes count as well as containers. Ports picked earlier in the same run are skipped too.
- Skip re-validating ports while the project's stack is already running, and re-validate a stale `.env` when it is not, so several stacks can be started back to back without colliding.
- Print the URLs it picked, and pass any arguments straight to `docker compose` (`./run.sh down`, `./run.sh logs -f`). With no arguments it runs `docker compose up --build -d`.
- With `share` as the first argument, start the project the same way and then give it a public HTTPS address through ngrok (see below).

Only the lines of the port variables in `.env` are touched: every other byte, including CRLF line endings, is kept. A stored port value that is not a positive number is replaced by the default.

`docker compose` has no pre-run hook, so a bare `docker compose up` cannot generate the `.env`. That is why a wrapper script exists. Bare `docker compose up --build` keeps working with the project's default ports, and does not need the submodule at all.

## Using a project that includes the launcher

Nothing special is needed. From the project folder:

```
./run.sh          # Git Bash, macOS, Linux
.\run.ps1         # PowerShell
```

If the `compose-launcher` folder is still empty (a plain `git clone` does not fill submodules), the stub runs `git submodule update --init compose-launcher` first. That one step needs network access and a real git clone: a zip download of the project has no submodule information, so there the stub stops with a message. To fetch the submodule up front, clone with `git clone --recurse-submodules <url>`, or run `git submodule update --init` in an existing clone.

In a PowerShell session use `run.ps1`. `bash ./run.sh` there resolves to `C:\WINDOWS\system32\bash.exe`, which is WSL and not Git Bash.

## Sharing a project through ngrok

```
./run.sh share          # Git Bash, macOS, Linux
.\run.ps1 share         # PowerShell
```

This starts the project as usual (or leaves it running), then runs `ngrok http <port>` for the project's port, so someone outside your network can open it. ngrok prints the public URL. Ctrl+C stops sharing, and the stack keeps running.

- It works only when `run.conf` has exactly one `port` line, so the launcher never has to guess which port is the web entry point. With more ports it stops before starting anything and lists them. Of the projects using the launcher, site and quoridor have one port. java-rest-example (app, phpMyAdmin, MySQL) and EZPoll (client, socket server, API, MySQL, phpMyAdmin) have several, and EZPoll could not work through a single tunnel anyway, because the browser also talks to its socket server directly.
- It needs [ngrok](https://ngrok.com/download) installed, on the PATH, and signed in once with `ngrok config add-authtoken <token>`. Nothing else in the launcher needs ngrok.
- Anything after `share` goes to ngrok, for example `./run.sh share --basic-auth "user:password"` to put a password in front of the page.
- Everyone with the URL can use the project. These projects run with development settings and have no real access control, so share only while you need to.
- How many tunnels can run at once, and whether the address stays the same between runs, depends on your ngrok plan.

## Adding the launcher to a project

From the project root:

```
git submodule add https://github.com/Nate314/compose-launcher.git compose-launcher
cp compose-launcher/stub/run.sh compose-launcher/stub/run.ps1 .
git update-index --add --chmod=+x run.sh
```

Then:

1. Write the project's `run.conf` (see the config format below).
2. Keep `run.sh`, `run.ps1` and `run.conf` as LF in every checkout, for example with `*.sh text eol=lf`, `*.ps1 text eol=lf` and `run.conf text eol=lf` in `.gitattributes`. Bash cannot run a CRLF script.
3. Add `compose-launcher` to `.dockerignore` so it stays out of the build context.
4. Commit `.gitmodules`, the `compose-launcher` entry, the two stubs and `run.conf`.

The submodule entry pins one exact commit of this repository, so a project keeps working the same way until it chooses to update.

## Updating a project after a launcher fix

1. Merge the fix here.
2. In the project: `git submodule update --remote compose-launcher`, then commit the changed `compose-launcher` entry on a branch and open a pull request.

There are no copies of the launcher to keep in sync. The stubs contain no launcher logic and should not need to change.

## Config format

`run.conf` is the only launcher file that differs between projects. It is plain text, one entry per line, words separated by spaces. Blank lines and lines starting with `#` are ignored, and anything else is an error.

| Line | Meaning |
| --- | --- |
| `port NAME DEFAULT` | A host port variable written to `.env`, and the port to start scanning from. The order of the lines is the order in which ports are picked. |
| `url TEXT` | A line printed after `up`. Every `{NAME}` is replaced by the chosen port. The text is printed as written, so labels can be aligned with spaces. |
| `note KEY\|KEY TEXT` | Prints TEXT after the ports were chosen when `.env` sets any of the keys. EZPoll uses it to warn about explicit `ALLOWED_ORIGINS` or `PUBLIC_SOCKET_URL` values. |

The config for java-rest-example:

```
port APP_PORT 8080
port PMA_PORT 8082
port MYSQL_PORT 3306

url App:        http://localhost:{APP_PORT}
url Swagger UI: http://localhost:{APP_PORT}/swagger-ui.html
url phpMyAdmin: http://localhost:{PMA_PORT}
url MySQL:      127.0.0.1:{MYSQL_PORT}
```

The port variable names must match the ones the project's `docker-compose.yml` interpolates (for example `"${APP_PORT:-8080}:8080"`). The real configs are in each project's root: [site](https://github.com/Nate314/site/blob/master/run.conf), [java-rest-example](https://github.com/Nate314/java-rest-example/blob/master/run.conf), [EZPoll](https://github.com/Nate314/EZPoll/blob/master/run.conf).

## Testing the launcher

`tests/test.sh` checks `run.sh` and `tests/test.ps1` checks `run.ps1`. Both copy the throwaway stack in `tests/fixture` (one `busybox` container publishing two ports) into temp folders, run the launcher from inside each folder against real `docker compose`, and remove everything they started. The five scenarios:

1. A native process holding the default port is skipped, and the second port skips the one just picked.
2. A rerun while the stack is running leaves `.env` and the container alone.
3. A second and a third stack started back to back get different ports without editing anything.
4. A stale `.env` is re-validated once the stack is stopped.
5. An existing `.env` with custom values keeps every byte, and only the missing port is appended.
6. `share` stops with a message and starts nothing when `run.conf` has more than one port.

```
bash tests/test.sh                                                     # Git Bash, macOS, Linux
pwsh -NoProfile -File tests/test.ps1                                   # PowerShell 7
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\test.ps1 # Windows PowerShell 5.1
```

The exit code is 0 when every check passes, 1 when a check fails, and 2 when the tests could not start. They need Docker and ports 18080 to 18087 and 18095 free, so run one of them at a time. `tests/test.sh` also needs `python3`, `python` or PowerShell for the native listener: that is a requirement of the test, not of the launcher.

Passing on Windows 11 in Git Bash, PowerShell 7 and Windows PowerShell 5.1. Not run on macOS or Linux yet, see [#3](https://github.com/Nate314/compose-launcher/issues/3). The stubs are not covered by these tests: they were checked by hand in the projects. Neither is a successful `share`, which needs an ngrok account and network access: it was checked by hand with quoridor.

## Why a submodule

The launcher started as project-specific scripts copied into three repositories (70 to 91 lines each, six files), which had already drifted apart. The first shared version was still copied into each project by a sync script, with a drift check to compare the copies. That removed the differences but kept about 250 lines of identical code in every project, and every fix needed a pull request per project just to move files.

With a submodule the launcher exists once, each project pins the commit it was tested with, and nothing can drift. The costs, accepted on purpose:

- A plain `git clone` leaves the `compose-launcher` folder empty, so the first `./run.sh` fetches it and needs network access.
- A zip download of a project cannot fetch it. Bare `docker compose up --build` still works there.
- Each project keeps two stub scripts of about a dozen lines.

## Design notes

- **Two implementations, bash and PowerShell, with identical behavior.** Running the launcher inside a container would leave a single implementation, but it would need a wrapper per shell anyway and could not probe the host's ports without host networking.
- **Port detection is connect only in both shells.** Bash cannot bind a port without an extra host tool. A port that is held but does not accept connections is therefore not detected.
- **`run.ps1` has no `param()` block**, here or in the stub. With one, PowerShell reads `-d` as its own `-Debug` switch, so `.\run.ps1 up --build -d` would lose the `-d`.
- **No new host dependency:** Docker and git only.
- **This repository is public** (since 2026-10-05), so that projects can use it as a submodule and link to it.

## Open questions

- Should first run generate random secrets into `.env` instead of shipping dev-only defaults? (Database passwords only apply when the data volume is first created, so this needs care.)
- Tests as a compose service, see [#2](https://github.com/Nate314/compose-launcher/issues/2): add an `e2e` service to each project's `docker-compose.yml` behind a `profiles` entry, so that `docker compose --profile e2e run --rm e2e` replaces the long `docker run` commands in the project READMEs. Not tried yet.

## Issues

- [#1](https://github.com/Nate314/compose-launcher/issues/1) Design and roll-out plan
- [#2](https://github.com/Nate314/compose-launcher/issues/2) Run the Playwright suites through a compose `e2e` service
- [#3](https://github.com/Nate314/compose-launcher/issues/3) Test the launchers on macOS, Linux and Windows PowerShell 5.1
