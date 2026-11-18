# Table of contents

- [Local n8n for macOS](#local-n8n-for-macos)
- [Local n8n for Windows 11 Users](#local-n8n-for-windows-11-users)
  - [First-run Windows prompts](#first-run-windows-prompts)
  - [Run again](#run-again)
  - [Settings](#settings)
  - [Terminal alternative](#terminal-alternative)
  - [Files and verification](#files-and-verification)
  - [Local storage and backups](#local-storage-and-backups)
  - [Planned work](#planned-work)

# Local n8n for macOS

Use `n8n-docker-compose-deploy-mac.command` in Finder or run the following from the repository root in Terminal:

```bash
bash n8n/n8n-docker-compose-deploy-mac.sh
```

For Finder, first allow execution once in Terminal:

```bash
chmod +x n8n/n8n-docker-compose-deploy-mac.command
```

Keep all files together. The launcher uses macOS's built-in Bash and supports Intel and Apple silicon through Docker Desktop's native image selection. It starts Docker Desktop, waits for its Linux engine, validates Compose, pulls the configured images, starts n8n and the external runner, waits for HTTP readiness and opens `http://localhost:5678/`. Set `N8N_OPEN_BROWSER=false` to skip browser opening. Create the owner account on the first visit.

If Docker is missing, the launcher asks before opening the official installation page. Install the download matching your processor, drag Docker to Applications, open it and complete onboarding, then rerun the launcher. Installation and license acceptance are interactive. See [Docker's macOS installation instructions and current requirements](https://docs.docker.com/desktop/setup/install/mac-install/). No Homebrew, WSL or PowerShell is required. The launcher supports Docker in `/Applications` or your user's `Applications` directory and always targets `desktop-linux`.

The Mac and Windows launchers share `.env.local.example`, `.env.local` and `n8n-compose-local.yaml`. Windows-only env settings are ignored on macOS. Existing encryption keys and runner tokens are preserved; exact `GENERATE_ON_FIRST_RUN` placeholders receive separate random secrets. Do not move an existing database without its original encryption key. The Mac launcher refuses to generate a replacement encryption key when `VLM_DATA` is already populated. It accepts `N8N_DATA_PATH=./VLM_DATA` only and rejects a symbolic link for that directory. There is no automatic storage migration.

Run these from any working directory using the actual path to the script:

```bash
bash n8n/n8n-docker-compose-deploy-mac.sh check  # Initialize/validate settings; no Docker startup
bash n8n/n8n-docker-compose-deploy-mac.sh status # Inspect Docker engine; no installation or startup
```

`check` creates `.env.local` if missing and resolves placeholders, so it changes local configuration. It does not render Compose. The Bash parser accepts `N8N_NAME=value` with optional enclosing quotes; it never executes shell expressions. Keep paths and values literal, without inline comments or variable expansion. The env file is saved with owner-only permissions. The UI binds to `127.0.0.1` only; a remote Docker context is rejected.

Use Ctrl+C to interrupt this launch. It does not stop Docker Desktop or containers already started. To stop the stack while retaining its data:

```bash
cd n8n
docker --context desktop-linux compose --env-file .env.local -f n8n-compose-local.yaml -p n8n-cmpsprj down
```

Use your configured `N8N_PROJECT_NAME` if changed. Rerun the launcher to start again. Back up `.env.local` and `VLM_DATA` together with n8n stopped. If Docker times out, complete its onboarding; if n8n times out, inspect its container logs in Docker Desktop. If the port is occupied, change `N8N_PORT` in `.env.local`. The directory lock `.n8n_macos_lock` is removed on normal exit and Ctrl+C. After a power loss, remove that empty lock directory only after confirming no launcher from this directory is running. macOS has no `cancel` argument that terminates other processes.

Verification: `bash n8n/n8n-test-macos.sh` runs isolated configuration and mocked deployment checks without installing software or starting containers. Real macOS installation, Finder permissions, Docker onboarding and native container execution still require testing on a Mac.

# Local n8n for Windows 11 Users

**Double-click `n8n-docker-compose-deploy-win.cmd`.** Keep the other files in the same `n8n` directory. You do not need a server, domain, Kubernetes, PostgreSQL, or manually generated passwords for this local setup.

The launcher checks Windows and virtualization, prepares WSL when necessary, installs Docker Desktop if it is missing, starts its Linux engine, and deploys n8n plus an external task runner. It creates `.env.local` and generates separate encryption/token values automatically. The browser opens after the readiness check succeeds:

Before each command, the console prints `Goal:` with a short explanation and `RUN:` with the actual executable and arguments. This covers system checks, administrator setup, WSL, installer download/signature verification, Docker startup, Compose validation/deployment, readiness testing and browser launch. Passwords and tokens are not included in these command lines. Native progress bars remain visible.

**[http://localhost:5678/](http://localhost:5678/)**

Create the n8n owner account in the browser on the first run. Docker Desktop does not need a Docker Hub login just to run this public-image stack; complete any required agreement screen in the Docker Desktop window.

## First-run Windows prompts

- Approve the Windows UAC prompt if WSL components need enabling. An administrator account/administrator credentials are required for that Windows operation.
- After UAC approval, a visible Administrator window shows Windows/WSL setup. WSL install/update runs directly in that console, preserving WSL's native percentage bar. A sufficiently recent WSL version is reused without updating. Docker Desktop installation uses its visible installer window, and Docker Compose runs directly in the original console with its native progress display. Timer messages are disabled for these operations.
- If a restart is required, save your work and restart Windows yourself. The launcher registers one continuation under your current user's `RunOnce` settings, so deployment resumes after the next login. Keep this folder in its current location until setup finishes. The script never forces an immediate restart.
- Docker Desktop may show its first-run agreement. Accept it to continue if you agree; the launcher waits for the engine. It does not accept Docker's license on your behalf.
- Firmware virtualization must already be enabled in BIOS/UEFI. If it is disabled, the launcher stops with a message; software cannot enable that firmware setting automatically.

Use a Docker-supported Windows 11 release and at least 8 GB RAM. Internet access is needed to download Docker/WSL updates and container images. School device policies can block installation; ask the device administrator if Windows denies the operation.

## Run again

Double-click the same file again. The project name and data path stay the same, preserving workflows, credentials, the owner account and SQLite data. Keep `.env.local`: its encryption key is required for saved credentials. Do not replace it with the server's `.env`.

The stack listens only on this PC's loopback interface. HTTP without a TLS certificate is used for this local learning instance. Internet services cannot call these localhost webhooks directly.

## Settings

The launcher creates `.env.local` from `.env.local.example` on its first run. Change settings only in `.env.local`; it is ignored by Git.

On every deployment launch, the launcher checks for `.env.local` and copies `.env.local.example` only if the runtime file is missing. It then checks every `N8N_*` variable in `.env.local`: an exact, case-sensitive `GENERATE_ON_FIRST_RUN` value (also accepted in single or double quotes) is replaced with an independent cryptographically random 32-byte secret encoded as 64 hexadecimal characters. This also resolves placeholders in an existing file. Existing values, including the encryption key, are preserved; comments and values containing the marker as only part of their text are left unchanged. Subsequent launches reuse the saved secrets. Never reset the encryption key for an existing installation.

| Setting | Default / effect |
| --- | --- |
| `N8N_PORT` | `5678`; change if another application occupies the port |
| `N8N_OPEN_BROWSER` | `true`; opens the UI automatically when ready |
| `N8N_VERSION` | Exact n8n/runner image version |
| `N8N_TIMEZONE` | `Europe/Moscow`; scheduled workflow timezone |
| `N8N_PROJECT_NAME` | `n8n-cmpsprj`; keep unchanged to reuse existing data |
| `N8N_DOCKER_TIMEOUT_SECONDS` | `600`; wait for Docker Desktop/onboarding |
| `N8N_STARTUP_TIMEOUT_SECONDS` | `240`; wait for n8n |

When changing `N8N_PORT`, the launcher prints and opens the new URL automatically. `N8N_HOST` stays `127.0.0.1`; the script rejects public listening addresses. It explicitly targets Docker Desktop's `desktop-linux` context, even if a different Docker context is currently selected.

## Terminal alternative

Double-click is sufficient. If you prefer Windows PowerShell, run the following from the `n8n` directory. All settings are loaded from `.env.local`; there are no values to replace in this command.

```powershell
# Windows 11 PowerShell.
.\n8n-docker-compose-deploy-win.cmd
# Expected: Local n8n is ready. Open: http://localhost:5678/
# If setup stops, read the displayed error and rerun the same launcher after resolving it.
```

The console stays open after errors. If Windows prerequisite preparation fails, see `.local-prerequisites.log` in this directory. If containers fail to start, the launcher prints their recent logs. When the engine wait times out, complete Docker Desktop's onboarding and launch the file again.

If another setup is running, the console prints a timestamped process snapshot and executable status/cancellation commands. PIDs can disappear after that snapshot: do not copy an old PID into taskkill. From the n8n directory, run `n8n-docker-compose-deploy-win.cmd status` to query current processes (approve UAC). If no setup exists now, the console says so and you can launch normally. To cancel a setup, run `n8n-docker-compose-deploy-win.cmd cancel`; it requests UAC, finds only prerequisite setup from this directory, and rechecks the process command and creation time before cancellation. Exited/reused PIDs and other copies are skipped. This cancels prerequisite work and its children but does not delete n8n data. Neither command installs Docker or changes Windows features. New Administrator windows are titled `n8n setup - Administrator - PID <number>`. The log command printed by the console is optional; no Task Manager search is required.

## Files and verification

`n8n-docker-compose-deploy-win.cmd` is the entry point. It calls `n8n-docker-compose-deploy-win.ps1`, which uses `n8n-compose-local.yaml` and `.env.local`. SQLite data lives in the local `./VLM_DATA` directory through an explicit bind mount at `/home/node/.n8n`. The local configuration stays in `.env.local`; no runtime server configuration is included in this repository.

The verification script checks configuration, generated-key stability, loopback restrictions, context restrictions and Compose rendering without installing software or starting containers:

```powershell
# Windows 11 PowerShell, from the n8n directory.
powershell -NoProfile -ExecutionPolicy Bypass -File .\n8n-test-local.ps1
# Expected: Local launcher checks passed; no software installed and no containers started.
# If a check fails, read the reported error to identify the configuration problem.
```

These checks do not exercise software installation, UAC prompts or Windows restarts. Those steps occur during first-run setup on Windows 11.

References: [Docker Desktop Windows installation and requirements](https://docs.docker.com/desktop/setup/install/windows-install/), [Microsoft WSL installation](https://learn.microsoft.com/windows/wsl/install).


## Planned work

Local webhook configuration will be added separately. This directory does not yet contain a webhook tunnel or DNS configuration script.

## Local storage and backups

Persistent storage uses an explicit bind mount from `N8N_DATA_PATH=./VLM_DATA` to `/home/node/.n8n`. Relative paths resolve from the directory containing `n8n-compose-local.yaml`, even when launching from another directory. Keep the data directory and the original encryption key together when backing up or moving the installation. If an earlier deployment used a Docker-managed volume, copy its data into this directory with n8n stopped before starting with the bind mount; changing the mount alone does not transfer existing data.
