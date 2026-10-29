# The Windows setup, interactive, on a Windows that has no distribution yet: every step and every
# question, the Linux user of the new distribution, the sudo password, then the stack installer (hidden
# while it works) and the summary. It installs Debian and the whole stack: record it on a disposable
# machine. Played on a Windows runner by record.mjs, in .github/workflows/demos.yml (README.md here).
Output docs/media/windows-setup.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1280
Set Height 900
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set WaitTimeout 120s

# What the elevated window shows: the bootstrap saved win11.ps1 and started it. Here it runs with the
# stack installer of this checkout, which the released one becomes.
Hide
Type "Set-Location install; Clear-Host; .\win11.ps1 -StackScript .\lamp-lapp-stack.sh"
Enter
Wait+Screen /Which Linux distribution/
Show

Sleep 2s
Type "1"
Sleep 500ms
Enter
Wait+Screen /Your choice \[1-5, Enter = 1\]/
Sleep 3s
Enter
Wait+Screen /Your choice \[1-3, Enter = 2\]/
Sleep 4s
Enter
Wait+Screen /Your choice \[1-2, Enter = 1\]/
Sleep 7s
Enter
Wait+Screen /\(WSLg\)\?.*\(y\/N\)/
Sleep 2s
Enter
Wait+Screen /up to 1 TB\. \(y\/N\)/
Sleep 2s
Type "y"
Sleep 400ms
Enter
Wait+Screen /Maximum size in GB/
Sleep 3s
Enter

# Steps 2 to 5: WSL, its update, .wslconfig, then the distribution asks for your Linux user.
Wait+Screen@15m /Enter new UNIX username/
Sleep 1s
Type "dev"
Enter
Wait+Screen /New password/
Type "wsl-demo-2026"
Enter
Wait+Screen /Retype new password/
Type "wsl-demo-2026"
Enter
Wait@3m /dev@.*\$ *$/
Sleep 1.5s
Type "exit"
Enter

Wait+Screen@3m /LAMP\/LAPP stack .*\(Y\/n\)/
Sleep 3s
Enter
Wait+Screen@5m /\[sudo\] password for dev/
Sleep 1s
Type "wsl-demo-2026"
Enter
Sleep 8s

# The stack installer prints a lot for many minutes: the recording skips to its end.
Hide
Wait+Screen@90m /Docker Desktop for Windows/
Show
Sleep 5s
Enter
Wait+Screen@5m /Setup completed/
Sleep 10s
