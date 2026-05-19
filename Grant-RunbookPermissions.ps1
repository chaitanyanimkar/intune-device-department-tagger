<#
.SYNOPSIS
    One-time setup: grants the Azure Automation Managed Identity the Graph API
    permissions needed to run Runbook-TagDevicesByDepartment.ps1.

.NOTES
    Run this ONCE from your local machine.
    Authenticates using stored DPAPI credentials (same as all other scripts).
    Requires your app registration to have:
        AppRoleAssignment.ReadWrite.All
        Application.Read.All
#>

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

$TENANT_ID               = "98f0543a-5a14-47f6-9d04-84909a8efe16"
$AUTOMATION_ACCOUNT_NAME = "sc-automations-prod"

$REQUIRED_ROLES = @(
    "Device.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All",
    "User.Read.All"
)

# Connect using stored DPAPI credentials — no browser, no WAM
$configDir  = "$env:APPDATA\SCGraphApp"
$clientId   = Get-Content "$configDir\clientId.txt"
$tenantId   = Get-Content "$configDir\tenantId.txt"
$secret     = Get-Content "$configDir\secret.txt" | ConvertTo-SecureString
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secret)
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

Write-Host "Connected to Graph (silent)" -ForegroundColor DarkGray

# Find the Managed Identity service principal for the Automation Account
$managedIdentity = Get-MgServicePrincipal -Filter "displayName eq '$AUTOMATION_ACCOUNT_NAME'" |
    Where-Object { $_.ServicePrincipalType -eq "ManagedIdentity" } |
    Select-Object -First 1

if (-not $managedIdentity) {
    throw "Managed Identity not found for '$AUTOMATION_ACCOUNT_NAME'. Ensure System-Assigned Managed Identity is enabled on the Automation Account in the Azure portal."
}

Write-Host "Found Managed Identity: $($managedIdentity.DisplayName) [$($managedIdentity.Id)]" -ForegroundColor Green

# Get the Microsoft Graph service principal to grant roles against
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

foreach ($roleName in $REQUIRED_ROLES) {
    $appRole = $graphSP.AppRoles | Where-Object {
        $_.Value -eq $roleName -and $_.AllowedMemberTypes -contains "Application"
    }

    if (-not $appRole) {
        Write-Warning "App role '$roleName' not found — skipping"
        continue
    }

    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentity.Id |
        Where-Object { $_.AppRoleId -eq $appRole.Id }

    if ($existing) {
        Write-Host "Already assigned: $roleName" -ForegroundColor DarkGray
        continue
    }

    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $managedIdentity.Id `
        -PrincipalId        $managedIdentity.Id `
        -ResourceId         $graphSP.Id `
        -AppRoleId          $appRole.Id | Out-Null

    Write-Host "Granted: $roleName" -ForegroundColor Green
}

Write-Host "`nDone. Managed Identity for '$AUTOMATION_ACCOUNT_NAME' has all required permissions." -ForegroundColor Cyan
