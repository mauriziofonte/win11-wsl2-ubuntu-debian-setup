# The Windows setup without questions: invalid options are refused before anything changes, then a
# dry run with options shows every step and the .wslconfig it would write.
# Recorded on a Windows runner by .github/workflows/demos.yml, from the repository root (README.md here).
Output docs/media/windows-options.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1280
Set Height 900
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set WaitTimeout 120s
Set WaitPattern /> *$/

Hide
Type "Set-Location install; Clear-Host"
Enter
Wait
Show

Type ".\win11.ps1 -Unattended -DryRun -WslMemoryGB 999 -WslNetworking bridged -VhdSizeGB 5"
Sleep 400ms
Enter
Wait+Screen /invalid options, nothing was changed/
Wait
Sleep 5s

Type "Clear-Host; .\win11.ps1 -Unattended -DryRun -Distro Ubuntu-26.04 -VmProfile Light -WslNetworking mirrored -VhdSizeGB 32 -Shell fish"
Sleep 400ms
Enter
Wait+Screen /Setup completed/
Wait
Sleep 8s
