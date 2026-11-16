# Repository Guidelines

## Project Structure & Module Organization

This repository currently contains a Windows 11 local n8n deployment. The CMD entry point invokes PowerShell. PowerShell loads `.env.local`, handles Windows/WSL and Docker Desktop prerequisites, and deploys `n8n_compose_local.yaml`. Compose runs n8n with persistent SQLite storage in the local ./VLM_DATA bind mount and a separate task runner. Both containers share the configured exact n8n version. The local UI binds only to loopback.

The `.env.local.example` file is a public template. The launcher creates `.env.local`, generates independent secrets on first use, and preserves them on later runs. Do not copy runtime settings, logs or credentials into examples. Domain examples use `dns-server-name.ru`; descriptions use `User`, and example identifiers use `user-name`.

## Build, Test, and Development Commands

Use `n8n/n8n_deploy_local.cmd` to deploy. Its `status` argument inspects current prerequisite processes; its `cancel` argument explicitly cancels a verified setup from the same directory. These operations are distinct from configuration tests.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\n8n\n8n_test_local.ps1` from the repository root for verification. This script checks generated-key stability, unsafe configuration rejection, live output, shared logs and process identity without installing software or starting containers. It renders Compose configuration when a local Docker CLI is available. Clean Windows installation, UAC and restart behavior require separate VM testing.

## Coding Style & Naming Conventions

Use English for documentation, comments and console output. Keep executable scripts' descriptions, usage and concrete examples at the start. Show each external command and its purpose before execution using the existing `Goal:` and `RUN:` output helpers. Preserve direct-console execution where native percentage bars require it.

PowerShell uses strict mode and terminating errors. Preserve the existing handling of shared log files, process creation-time checks and directory-specific cancellation. Follow `.editorconfig` and `.gitattributes`: Windows launcher files use CRLF; shell scripts use LF. Do not replace an existing runtime encryption key while changing deployment behavior.

## Documentation Structure

For `tunnels`, follow the Russian-language specification: user-facing documentation and messages are in Russian and address the user without the word "student". Keep exactly three provider launch scripts under `tunnels`, named `tunnels_start_cloudflare.ps1`, `tunnels_start_ngrok.ps1` and `tunnels_start_localtunnel.ps1`, with shared helpers as needed. Use UTF-8 with BOM for Russian PowerShell files so Windows PowerShell 5.1 decodes them correctly; retain CRLF. Only publish loopback HTTP services, require consent for dependency installation/downloads, do not send webhook POST automatically, do not change application/provider configurations, and terminate only processes owned by the current launch. Keep authtokens out of arguments, logs and repository files. Use `tunnels/tunnels_readme.md` for the central runbook.

Keep the root `README.md` as a stable directory index. For each project directory, use a heading matching its directory name, a short general description and a relative link to its own documentation. Update the root index only when directories, their purpose or documentation links change.

Keep installation, configuration, commands, troubleshooting, verification and planned work in the corresponding project directory. Name each directory's main documentation file `<service>_readme.md`, using the short service or entity name first; for example, `n8n/n8n_readme.md`. Use lowercase filenames and update all links when renaming documentation. Maintain detailed documentation alongside changes to that project instead of duplicating it in the root README.

## Environment Variables and Persistent Storage

Start service-specific variables in every env file (including ignored runtime files and public templates) with a short service prefix, such as `N8N_`. Place the service name only at the beginning: use `N8N_PROJECT_NAME` and `N8N_VERSION`. Do not include environment names such as LOCAL in variable names. Use identical variable names across env files; select environment-specific values through the env filename, such as `.env.local`. Update scripts, Compose interpolation, tests and documentation together when renaming variables, preserving runtime values and existing encryption keys. Keep container environment names required by upstream applications unchanged.

Declare all persistent mounts explicitly as bind mounts with `type`, `source` and `target`. Store their data inside the corresponding project directory, relative to its Compose file, regardless of the terminal's working directory. For n8n, use `N8N_DATA_PATH=./VLM_DATA` mounted at `/home/node/.n8n`. Do not use anonymous volumes or Docker-managed named volumes for persistent project data. Exclude data directories from Git. Preserve existing data and document any storage migration; changing a mount does not migrate data automatically.

## File Naming and Agent Communication

Start project-specific filenames with the entity or short service name, followed by the action or role, then the environment when applicable. Use lowercase words separated by underscores: `n8n_deploy_local.ps1`, `n8n_deploy_local.cmd`, `n8n_test_local.ps1`, `n8n_compose_local.yaml` and `n8n_readme.md`. Keep conventional discovery filenames such as root `README.md`, `AGENTS.md`, `.env.local`, `.env.local.example`, `.gitignore` and `.editorconfig` unchanged. When renaming files, update all references, process identity checks, diagnostic commands, tests and documentation together.

Record new or changed repository rules and persistent user preferences in `AGENTS.md` as part of the task. Explicitly tell the user in your response that you updated `AGENTS.md` and which rules you recorded. Also state which MCP server you use for the task, including Serena, and distinguish actual MCP operations from local shell commands and browser tools. Use Serena first for code search, navigation, semantic analysis and supported edits; read its initial instructions and `global/user_preferences/serena` memory before first use. If Serena is unavailable, check the connection, attempt to restore it and report any remaining limitation.
