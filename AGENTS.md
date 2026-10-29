# AGENTS.md

A guide for coding agents (and people) who change this repository. Read it before your first edit.

## What this repository is

A guide, in English and Italian, that sets up a LAMP/LAPP development stack on Windows 11 inside WSL2 (Debian 13, Ubuntu 24.04, Ubuntu 26.04), and the installers that do what the guide says:

* `install/install.ps1`: the bootstrap behind `irm https://wsl.mauriziofonte.it | iex`. It downloads `win11.ps1` and starts it elevated, passing every option through.
* `install/win11.ps1`: the Windows setup, in eight steps: checks and questions, WSL, WSL update, `.wslconfig`, distribution, stack, Docker Desktop, shortcuts.
* `install/lamp-lapp-stack.sh`: the stack installer, run inside the distribution (or on a plain Debian/Ubuntu machine).

`wsl.mauriziofonte.it` serves the files of the latest GitHub release, so a change reaches users only when the maintainer tags a release. Never tag, never merge: open a pull request.

## Layout

| Path | What |
|---|---|
| `README.md` | Overview, the automated install, its options |
| `docs/en/SETUP-EN.md`, `docs/it/SETUP-IT.md` | The manual guide, one per language, kept in parity |
| `docs/tapes/`, `docs/media/` | VHS tapes and the GIFs they record (see `docs/tapes/README.md`) |
| `install/` | The installers (above) |
| `confs/vscode.json` | VS Code remote settings the guide links |
| `tests/` | What CI runs: see `tests/README.md` |
| `.github/workflows/ci.yml` | CI: lint, PowerShell, real WSL2 on Windows, plain machines in containers |
| `.github/workflows/demos.yml` | Records the GIFs on a Windows runner |

## Rules that the checks enforce

The guide states facts, and CI checks them; a change that breaks a fact breaks the build. Keep these in step:

* **Options.** A new option of `lamp-lapp-stack.sh` goes in its parser, its `--help` and the options table of section 4 of both guides. A new parameter of `win11.ps1` goes in its `param` block, in `install/install.ps1` (passed through), in `Get-SelfArguments` (kept through elevation and the resume after a reboot), in its validation in step 1, and in the README options table. `tests/check-docs.py` compares all of them.
* **Versions.** `LLS_VERSION` and `$scriptVersion` match, and so do the `# Version:` headers and the README's sample banner. PHP, MariaDB, PostgreSQL and nvm versions are read from the installer and compared with the guides and with `tests/verify-stack.sh`.
* **The two guides.** Same sections, same tables (row counts), same code blocks (comments may be translated), same links. Change both in the same commit, and the "last updated" date of both.
* **Blocks that CI runs.** A fenced block after `<!-- ci:run NAME -->` is executed as written (the first local site, the manual steps). `<!-- ci:profiles -->` and `<!-- ci:wslconfig -->` mark the profile table and the `.wslconfig` example that `tests/powershell/unit.ps1` recomputes with the functions of `win11.ps1`.
* **Gash.** Every Gash command and function that the documents name must exist in the current Gash, with those flags: `GASH_REPO=<checkout> python3 tests/check-docs.py` checks it against a Gash checkout.
* **Encodings.** `install/install.ps1` is ASCII without a BOM (it runs through `Invoke-Expression`). `install/win11.ps1` has Italian text and must keep its UTF-8 BOM (Windows PowerShell 5.1 reads a file without a BOM as ANSI). Other `.ps1` files stay ASCII (use `è`-style escapes in regexes). Line endings are LF everywhere (`.gitattributes`).
* **Converging installers.** Both installers must be safe to run again: each step checks the state and changes only what differs. The stack installer reports each change on a line of its own (`  wrote ...`, `  linked ...`, `  installed ...`, `  disabled ...`, `  removed ...`): CI runs it twice and fails if the second run prints one.
* **Messages.** Every message of `win11.ps1` exists in English and Italian (`$messages`). Both languages tell the user the same thing.

## Checks to run before you push

```bash
git ls-files -z '*.sh' | xargs -0 shellcheck -S info     # ShellCheck v0.11.0 in CI
actionlint                                              # if you touched a workflow
GASH_REPO=../gash python3 tests/check-docs.py           # the documents against the installers and Gash
bash install/lamp-lapp-stack.sh --help                  # still prints the options
```

With PowerShell available: `pwsh tests/powershell/unit.ps1`. `tests/powershell/dry-run.ps1` needs Windows. The stack itself can only be checked where systemd runs in a container (`tests/container/run.sh IMAGE SCENARIO`, see `tests/README.md`) or on a real WSL2 (`tests/wsl/run.ps1`, on a disposable Windows only: it installs a distribution and edits the Windows hosts file).

CI runs on pull requests, on pushes to `main`, every Monday, and by hand (`workflow_dispatch`). The WSL2 jobs take about an hour.

## Conventions

* English in every file of the repository except the Italian guide and the Italian messages of `win11.ps1`.
* Commits: conventional one-line messages (`feat: ...`, `fix(ci): ...`, `docs: ...`).
* Write for the reader of the guide: say what a command does and why, in plain sentences. Comments in the scripts explain why, not what.
* Pin what you download: GitHub Actions by commit SHA, release binaries by version and SHA-256 (see `LLS_STARSHIP_*`), installers by version (`LLS_NVM_VERSION`).
* Examples use neutral names (`dev`, `shop.test`, `Debian`). Never commit personal notes, private documents, host names, user names or credentials, including in tests, tapes and commit messages.

## WSL facts worth knowing

* `.wslconfig` (Windows, `%UserProfile%`) configures the WSL virtual machine; `/etc/wsl.conf` (inside each distribution) configures that distribution. Changes apply after `wsl --shutdown` (or `wsl --terminate <distro>` for `wsl.conf`).
* `win11.ps1` merges into an existing `.wslconfig` (`Merge-IniText`): it sets its keys in place and keeps every other line. Unattended, it changes an existing file only for the options given.
* Mirrored networking needs Windows 11 22H2 (build 22621). `wsl --install --vhd-size` and `wsl --manage --resize` need WSL 2.5.
* GitHub's `windows-2025` runners run a real WSL2 with systemd: `tests/wsl/run.ps1` and the GIF recordings use that.
