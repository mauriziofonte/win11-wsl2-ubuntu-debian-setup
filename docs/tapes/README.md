# The GIFs of the guide

The GIFs in `docs/media` come from the tapes in this folder, played on a real Windows with WSL2: a GitHub Windows runner, through the [Demos workflow](/.github/workflows/demos.yml).

| Tape | GIF | What it shows |
|---|---|---|
| [windows-options.tape](windows-options.tape) | `windows-options.gif` | `win11.ps1 -Unattended -DryRun`: invalid options refused before anything changes, then a dry run with options |
| [windows-setup.tape](windows-setup.tape) | `windows-setup.gif` | The interactive setup on a Windows without distributions: every step and question, the Linux user, the sudo password, the summary (the stack installer's own output is skipped) |
| [first-site.tape](first-site.tape) | `first-site.gif` | The guide's "first local site" in the new Debian, then `curl.exe` on Windows opens it |

The tapes are written in the tape language of [VHS](https://github.com/charmbracelet/vhs), but VHS hangs on the Windows runners (the terminal server it relies on never starts the shell there). [record.mjs](record.mjs) plays them instead: it types into a real Windows console (ConPTY, through node-pty), waits on the screen the way VHS does (a headless xterm.js keeps it), and saves what the console shows as an asciicast. [agg](https://github.com/asciinema/agg) then turns each asciicast into a GIF, with the colors of the tapes' theme. `record.mjs` understands `Output`, `Set`, `Hide`, `Show`, `Type`, `Enter`, `Sleep` and `Wait` (with `+Screen`, `+Line` and `@time`); a `Wait` that does not match in time stops the recording and prints the screen.

The tapes run in this order, from the repository root, and `windows-setup.tape` installs Debian and the whole stack: run them only on a disposable Windows machine with WSL2, such as a CI runner:

```powershell
npm ci --prefix docs/tapes
node docs/tapes/record.mjs docs/tapes/windows-options.tape windows-options.cast
```

The workflow runs when a push to a branch other than `main` changes a tape (or the workflow), and commits the GIFs to that branch: they reach `main` with the pull request. Started by hand (`workflow_dispatch`), it commits them only with `commit` checked. Each run also uploads the GIFs as an artifact.
