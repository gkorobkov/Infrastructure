# Repository Guidelines

Name local n8n Docker Compose deployment launchers `n8n-docker-compose-deploy-win.cmd` / `.ps1` for Windows and `n8n-docker-compose-deploy-mac.command` / `.sh` for macOS. The OS suffix replaces the previous `local` suffix for these launchers. Keep environment filenames unchanged; update launcher references, resume commands, process identity checks, tests and documentation together when renaming.

macOS local n8n uses `n8n/n8n-docker-compose-deploy-mac.command` (Finder) and `n8n/n8n-docker-compose-deploy-mac.sh` (Bash 3.2 compatible, LF). Reuse the shared Compose file, `.env.local`, and `./VLM_DATA`; never evaluate env files as shell code or regenerate an existing data directory's encryption key. macOS `status` queries the Docker engine, `check` initializes/validates configuration, and Ctrl+C interrupts the current launch without killing Docker or deleting data. Docker Desktop installation and license acceptance remain interactive. Verify on a real Mac before claiming native installation coverage.

## Project Structure & Module Organization

This repository currently contains a Windows 11 local n8n deployment. The CMD entry point invokes PowerShell. PowerShell loads `.env.local`, handles Windows/WSL and Docker Desktop prerequisites, and deploys `n8n-compose-local.yaml`. Compose runs n8n with persistent SQLite storage in the local ./VLM_DATA bind mount and a separate task runner. Both containers share the configured exact n8n version. The local UI binds only to loopback.

The `.env.local.example` file is a public template. The launcher creates `.env.local`, generates independent secrets on first use, and preserves them on later runs. Do not copy runtime settings, logs or credentials into examples. Domain examples use `dns-server-name.ru`; descriptions use `User`, and example identifiers use `user-name`.

## Build, Test, and Development Commands

Use `n8n/n8n-docker-compose-deploy-win.cmd` to deploy. Its `status` argument inspects current prerequisite processes; its `cancel` argument explicitly cancels a verified setup from the same directory. These operations are distinct from configuration tests.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\n8n\n8n-test-local.ps1` from the repository root for verification. This script checks generated-key stability, unsafe configuration rejection, live output, shared logs and process identity without installing software or starting containers. It renders Compose configuration when a local Docker CLI is available. Clean Windows installation, UAC and restart behavior require separate VM testing.

## Coding Style & Naming Conventions

Use English for documentation, comments and console output. Keep executable scripts' descriptions, usage and concrete examples at the start. Show each external command and its purpose before execution using the existing `Goal:` and `RUN:` output helpers. Preserve direct-console execution where native percentage bars require it.

PowerShell uses strict mode and terminating errors. Preserve the existing handling of shared log files, process creation-time checks and directory-specific cancellation. Follow `.editorconfig` and `.gitattributes`: Windows launcher files use CRLF; shell scripts use LF. Do not replace an existing runtime encryption key while changing deployment behavior.

## Documentation Structure

Keep tunnel architecture provider/client-neutral: use `Web UI https://service-name.ru` as a placeholder, allow any external client, and refer to the actual UI origin for CORS. Keep the architecture independent of any particular site. Do not hardcode, advertise or assume any specific website as a default proxy client.

Write README files for students and operators: describe the directory's purpose, system behavior, architecture, configuration, command examples and operational runbooks. Keep agent instructions, repository editing conventions and reminders about past agent mistakes in `AGENTS.md`, not in README files.

For `tunnels`, follow the Russian-language specification: user-facing documentation and messages are in Russian and address the user without the word "student". Keep exactly three provider launch scripts under `tunnels`, named `tunnels-start-cloudflare.ps1`, `tunnels-start-ngrok.ps1` and `tunnels-start-localtunnel.ps1`, with shared helpers as needed. Use UTF-8 with BOM for Russian PowerShell files so Windows PowerShell 5.1 decodes them correctly; retain CRLF. Only publish loopback HTTP services, require consent for dependency installation/downloads, do not send webhook POST automatically, do not change application/provider configurations, and terminate only processes owned by the current launch. Keep authtokens out of arguments, logs and repository files. Use `tunnels/tunnels-readme.md` for the central runbook.

Keep the root `README.md` as a stable directory index. For each project directory, use a heading matching its directory name, a short general description and a relative link to its own documentation. Update the root index only when directories, their purpose or documentation links change.

Keep installation, configuration, commands, troubleshooting, verification and planned work in the corresponding project directory. Name each directory's main documentation file `<service>-readme.md`, using the short service or entity name first; for example, `n8n/n8n-readme.md`. Use lowercase filenames and update all links when renaming documentation. Maintain detailed documentation alongside changes to that project instead of duplicating it in the root README.

## Environment Variables and Persistent Storage

Start service-specific variables in every env file (including ignored runtime files and public templates) with a short service prefix, such as `N8N_`. Place the service name only at the beginning: use `N8N_PROJECT_NAME` and `N8N_VERSION`. Do not include environment names such as LOCAL in variable names. Use identical variable names across env files; select environment-specific values through the env filename, such as `.env.local`. Update scripts, Compose interpolation, tests and documentation together when renaming variables, preserving runtime values and existing encryption keys. Keep container environment names required by upstream applications unchanged.

Declare all persistent mounts explicitly as bind mounts with `type`, `source` and `target`. Store their data inside the corresponding project directory, relative to its Compose file, regardless of the terminal's working directory. For n8n, use `N8N_DATA_PATH=./VLM_DATA` mounted at `/home/node/.n8n`. Do not use anonymous volumes or Docker-managed named volumes for persistent project data. Exclude data directories from Git. Preserve existing data and document any storage migration; changing a mount does not migrate data automatically.

## File Naming and Agent Communication

Start project-specific filenames with the entity or short service name, followed by the action or role, then the environment when applicable. Use lowercase words separated by hyphens: `n8n-docker-compose-deploy-win.ps1`, `n8n-docker-compose-deploy-win.cmd`, `n8n-test-local.ps1`, `n8n-compose-local.yaml` and `n8n-readme.md`. Keep conventional discovery filenames such as root `README.md`, `AGENTS.md`, `.env.local`, `.env.local.example`, `.gitignore` and `.editorconfig` unchanged. When renaming files, update all references, process identity checks, diagnostic commands, tests and documentation together.

Record new or changed repository rules and persistent user preferences in `AGENTS.md` as part of the task. Explicitly tell the user in your response that you updated `AGENTS.md` and which rules you recorded. Also state which MCP server you use for the task, including Serena, and distinguish actual MCP operations from local shell commands and browser tools. Use Serena first for code search, navigation, semantic analysis and supported edits; read its initial instructions and `global/user_preferences/serena` memory before first use. If Serena is unavailable, check the connection, attempt to restore it and report any remaining limitation.

Do not rename, move or replace a CMD launcher while it is executing, including while it waits at `pause`. Let the user finish the running launcher before renaming it: cmd.exe reads subsequent commands from the batch file and can report `The batch file cannot be found.` if the file disappears. Launch the new filename afterward. Discard intentionally unused PowerShell command output with `$null = ...` instead of assigning an unread variable; preserve result objects when their exit code or output is used.

## Universal HTTP Proxy

Use Universal HTTP Proxy and universal-http-proxy in product names, package identifiers, health responses, executable artifacts and CI. Do not qualify the general solution as Local; use local only when describing commands run on the user's computer. Preserve technical localhost/.local address checks and loopback/SSRF restrictions. Prioritize macOS Apple Silicon and Intel: keep launchers POSIX/Bash 3.2 compatible and provide a Finder .command entry point. A single OS entry point must check components, report present/missing status, offer required dependency installation with approximate download/disk sizes and [Y/n] (Enter accepts), and stop on refusal. Download runtime archives only after consent; prefer a private verified runtime without administrator access or system PATH changes. Cover launcher behavior and both Mac architectures in CI; distinguish simulated checks from actual native Mac results.

The `proxy/` directory is a provider-neutral, loopback-only browser HTTP proxy. Keep `proxy/src` independent of every particular UI, website and named external API; the client sends the Original URL in `X-Proxy-Target-URL`. Maintain exact Origin/Host checks, public-address-only DNS pinning and per-redirect validation. Never remove SSRF protections or log API keys, request bodies, response bodies or query secrets for debugging. No Docker, YAML configuration, certificate setup or web dashboard for the initial user scenario. Use the service prefix and lowercase hyphen-separated names in new service files. The main runbook is `proxy/proxy-readme.md`; update it and its tests whenever behavior changes. Run `cd proxy && npm test` before committing proxy changes. Build executable artifacts only on their target operating systems and never claim an unverified binary is usable.
The generic HTTP proxy must not mention, bundle, or preauthorize named third-party client websites. Public web origins are explicitly approved through repeatable `--allow-origin` or `PROXY_ALLOWED_ORIGINS`; default origins are loopback development sites only. Keep executable names, package identifiers, logs, API service IDs, examples and CI artifacts generic.

Use hyphens (-) as the default word separator in all project-specific filenames, including command launchers, helpers, source files, tests, Compose files, CI workflows and documentation. Preserve conventional discovery filenames, environment variable names and existing persistent data directory names. Update references, import paths, glob patterns, process identity checks, commands and documentation together when renaming files.

Proxy defaults must support exact HTTP(S) loopback browser origins (localhost, 127.0.0.1 and [::1]) on arbitrary ports, rejecting lookalike hosts and non-origin URLs. Keep public origins explicitly approved. CLI launches must persist diagnostic logs by default, print their path and record request IDs/status/error codes without headers, target URLs, query strings or bodies.

Do not prepopulate or print fixed loopback development origins for the proxy. Show the additional exact browser origins section only when origins are explicitly configured.
