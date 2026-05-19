<#
.SYNOPSIS
    AD Department Audit — Fixed version
    Audits AD users for department field population.
    Run this first to validate your AD data quality before tagging devices.
#>

#Requires -Modules ActiveDirectory

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "AD_Department_Audit_$timestamp.csv"
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

Write-Host "Retrieving Active Directory users..." -ForegroundColor Cyan

$allUsers = Get-ADUser -Filter { Enabled -eq $true } `
    -Properties DisplayName, Department, UserPrincipalName, Manager

foreach ($user in $allUsers) {

    # Safely resolve manager name — guard against null Manager attribute
    $managerName = if ($user.Manager) {
        try { (Get-ADUser -Identity $user.Manager -ErrorAction Stop).Name }
        catch { "Lookup Failed" }
    }
    else {
        "No Manager Set"
    }

    # Treat null AND empty string as "not populated"
    $deptPopulated = -not [string]::IsNullOrWhiteSpace($user.Department)

    $results.Add([PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Department        = if ($deptPopulated) { $user.Department } else { "NOT SET" }
            ManagerName       = $managerName
            Status            = if ($deptPopulated) { "Department Populated" } else { "Department Missing" }
        })
}

$withDept = $results | Where-Object { $_.Status -eq "Department Populated" }
$withoutDept = $results | Where-Object { $_.Status -eq "Department Missing" }

Write-Host "`nUsers with Department populated : $($withDept.Count)" -ForegroundColor Green
Write-Host "Users without Department        : $($withoutDept.Count)" -ForegroundColor Yellow

$results | Sort-Object Status, DisplayName | Export-Csv -Path $logFile -NoTypeInformation
Write-Host "`nExported to: $logFile" -ForegroundColor Cyan