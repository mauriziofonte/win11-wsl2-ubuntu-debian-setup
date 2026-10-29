# The GIFs of the guide

The GIFs in [docs/media](../media) are recorded with [VHS](https://github.com/charmbracelet/vhs) from the tapes in this folder, on a real Windows with WSL2: a GitHub Windows runner, through the [Demos workflow](/.github/workflows/demos.yml).

| Tape | GIF | What it shows |
|---|---|---|
| [windows-options.tape](windows-options.tape) | `windows-options.gif` | `win11.ps1 -Unattended -DryRun`: invalid options refused before anything changes, then a dry run with options |
| [windows-setup.tape](windows-setup.tape) | `windows-setup.gif` | The interactive setup on a Windows without distributions: every step and question, the Linux user, the sudo password, the summary (the stack installer's own output is skipped) |
| [first-site.tape](first-site.tape) | `first-site.gif` | The guide's "first local site" in the new Debian, then `curl.exe` on Windows opens it |

The tapes run in this order, from the repository root, and `windows-setup.tape` installs Debian and the whole stack: run them only on a disposable Windows machine with WSL2, such as a CI runner.

The workflow runs on a pull request that changes a tape, and uploads the GIFs as an artifact. Started by hand (`workflow_dispatch`) with `commit` checked, it also commits them to the branch it ran on.
