# Import the Active Directory module
Import-Module ActiveDirectory

# Get timestamp for log file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "AD_Department_Audit_$timestamp.csv"

# Get all enabled AD users
Write-Host "Retrieving Active Directory users..."

# Users with department field populated
$usersWithDept = Get-ADUser -Filter {(Enabled -eq $true) -and (Department -like "*")} -Properties DisplayName, Department, UserPrincipalName, Manager |
    Select-Object DisplayName, UserPrincipalName, Department, @{Name="ManagerName";Expression={(Get-ADUser $_.Manager).Name}}

# Users without department field
$usersWithoutDept = Get-ADUser -Filter {(Enabled -eq $true) -and (Department -notlike "*")} -Properties DisplayName, Department, UserPrincipalName, Manager |
    Select-Object DisplayName, UserPrincipalName, Department, @{Name="ManagerName";Expression={(Get-ADUser $_.Manager).Name}}

# Display results
Write-Host "`nUsers with Department field populated: $($usersWithDept.Count)"
Write-Host "Users without Department field populated: $($usersWithoutDept.Count)"

# Export results to CSV
$results = @()
foreach ($user in $usersWithDept) {
    $results += [PSCustomObject]@{
        DisplayName = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        Department = $user.Department
        ManagerName = $user.ManagerName
        Status = "Department Populated"
    }
}

foreach ($user in $usersWithoutDept) {
    $results += [PSCustomObject]@{
        DisplayName = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        Department = "Not Set"
        ManagerName = $user.ManagerName
        Status = "Department Missing"
    }
}

# Export to CSV
$results | Export-Csv -Path $logFile -NoTypeInformation

Write-Host "`nResults exported to: $logFile"