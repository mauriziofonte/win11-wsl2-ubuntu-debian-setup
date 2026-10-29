# PSScriptAnalyzer settings for install/*.ps1 and tests/wsl/*.ps1 (CI job "PowerShell").
@{
    Severity     = @("Error", "Warning")
    ExcludeRules = @(
        # Interactive installers: colored console output is the point.
        "PSAvoidUsingWriteHost",
        # Setup helpers that change state on purpose, after the user's answer; no -WhatIf layer (-DryRun covers it).
        "PSUseShouldProcessForStateChangingFunctions",
        # Get-InstalledDistros, Get-SelfArguments: the plural is what they return.
        "PSUseSingularNouns"
    )
}
