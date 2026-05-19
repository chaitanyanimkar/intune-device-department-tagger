<#
.SYNOPSIS
    Inspects a device's Intune primary user, their department, and the device's
    current extensionAttribute10 value in Entra ID.
    Authenticates silently via app registration stored in Windows Credential Manager.

.PARAMETER DeviceName
    The Intune device name.

.EXAMPLE
    .\CheckDepartment\Check1devicedept.ps1 -DeviceName "SCB-LPT213"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceName
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, CredentialManager

function Connect-SCGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph silently using app registration credentials
        stored in Windows Credential Manager. No browser, no device code, no prompts.
    .NOTES
        One-time setup required — run Store-SCGraphCredentials.ps1 once per machine.
    #>
    try {
        $clientId = (Get-StoredCredential -Target "SC-GraphApp-ClientId" -ErrorAction Stop).GetNetworkCredential().Password
        $tenantId = (Get-StoredCredential -Target "SC-GraphApp-TenantId" -ErrorAction Stop).GetNetworkCredential().Password
        $secret   = (Get-StoredCredential -Target "SC-GraphApp-Secret"   -ErrorAction Stop).GetNetworkCredential().Password |
                    ConvertTo-SecureString -AsPlainText -Force

        $clientSecretCred = New-Object System.Management.Automation.PSCredential($clientId, $secret)
        Connect-MgGraph -ClientId $clientId -TenantId $tenantId -ClientSecretCredential $clientSecretCred -NoWelcome
        Write-Host "Connected to Graph (app-only, silent)" -ForegroundColor DarkGray
    }
    catch {
        throw "Graph connection failed. Have you run Store-SCGraphCredentials.ps1 on this machine? Error: $($_.Exception.Message)"
    }
}

Connect-SCGraph

Write-Host "`nChecking device: $DeviceName" -ForegroundColor Cyan

# Try server-side filter first, fall back to client-side scan if it returns nothing
Write-Host "Querying Intune..." -ForegroundColor DarkGray
$intuneDevice = Get-MgDeviceManagementManagedDevice `
    -Filter "deviceName eq '$DeviceName'" `
    -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $intuneDevice) {
    Write-Host "Server-side filter returned nothing — falling back to full scan..." -ForegroundColor DarkGray
    $intuneDevice = Get-MgDeviceManagementManagedDevice `
        -Filter "operatingSystem eq 'Windows'" -All `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -ieq $DeviceName } |
        Select-Object -First 1
}

if (-not $intuneDevice) {
    Write-Host "`nDevice not found in Intune: $DeviceName" -ForegroundColor Red
    return
}

Write-Host "Found in Intune ✓" -ForegroundColor Green

if (-not $intuneDevice.UserId) {
    Write-Host "`nNo primary user assigned to this device in Intune." -ForegroundColor Yellow
} else {
    $user = Get-MgUser -UserId $intuneDevice.UserId `
        -Select "Id,DisplayName,Department,UserPrincipalName" `
        -ErrorAction SilentlyContinue

    Write-Host "`n--- Primary User ---" -ForegroundColor Yellow
    Write-Host "Display Name : $($user.DisplayName)"
    Write-Host "UPN          : $($user.UserPrincipalName)"
    if ($user.Department) {
        Write-Host "Department   : $($user.Department)" -ForegroundColor Green
    } else {
        Write-Host "Department   : (NOT SET)" -ForegroundColor Red
    }
}

$aadDevice = Get-MgDevice `
    -Filter "displayName eq '$($intuneDevice.DeviceName)'" `
    -Select "id,displayName,extensionAttributes" `
    -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $aadDevice) {
    Write-Host "`nDevice not found in Entra ID." -ForegroundColor Red
    return
}

Write-Host "`n--- Entra ID Device ---" -ForegroundColor Yellow
Write-Host "Display Name : $($aadDevice.DisplayName)"
Write-Host "Device ID    : $($aadDevice.Id)"

$extAttr10 = $null
if ($aadDevice.ExtensionAttributes) {
    $extAttr10 = $aadDevice.ExtensionAttributes.ExtensionAttribute10
}
if (-not $extAttr10 -and $aadDevice.AdditionalProperties.extensionAttributes) {
    $extAttr10 = $aadDevice.AdditionalProperties.extensionAttributes.extensionAttribute10
}

if ($extAttr10) {
    Write-Host "extensionAttribute10 : $extAttr10" -ForegroundColor Green
} else {
    Write-Host "extensionAttribute10 : (not set)" -ForegroundColor Yellow
    Write-Host "Run TagDevice.ps1 -DeviceName '$DeviceName' to tag this device." -ForegroundColor Cyan
}
