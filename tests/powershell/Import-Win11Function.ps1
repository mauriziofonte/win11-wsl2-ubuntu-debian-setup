# Defines the WSL settings functions of install/win11.ps1 in the caller's scope, without running the
# installer: dot-source it.
#
#   . tests/powershell/Import-Win11Function.ps1
#
# Author: Maurizio Fonte (https://www.mauriziofonte.it)
# License: MIT License

$win11Script = (Resolve-Path (Join-Path $PSScriptRoot "../../install/win11.ps1")).Path
$win11Functions = @("Get-VmProfiles", "Get-SwapGB", "Get-VhdProposal", "Read-IniValues", "Merge-IniText", "Get-IniChange",
    "Get-WslSettings", "Get-HostResources")
$parseErrors = $null
$win11Ast = [System.Management.Automation.Language.Parser]::ParseFile($win11Script, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw "$win11Script does not parse: $($parseErrors[0].Message)" }
$win11Found = @()
foreach ($definition in $win11Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($win11Functions -contains $definition.Name) {
        . ([ScriptBlock]::Create($definition.Extent.Text))
        $win11Found += $definition.Name
    }
}
$win11Missing = @($win11Functions | Where-Object { $win11Found -notcontains $_ })
if ($win11Missing.Count -gt 0) { throw "not in ${win11Script}: $($win11Missing -join ', ')" }
