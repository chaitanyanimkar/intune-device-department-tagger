<#
.SYNOPSIS
    Tags a single Intune-enrolled Windows device's extensionAttribute10 with the
    primary user's department from Entra ID.

.DESCRIPTION
    Resolves the device in Intune, looks up the primary user's Department field,
    then writes it to extensionAttribute10 on the Entra ID device object via
    Microsoft Graph. Skips the write if the attribute is already correct.

.PARAMETER DeviceName
    The Intune device name (case-insensitive).

.PARAMETER WhatIf
    Report what would change without writing anything.

.EXAMPLE
    .\TagDevice.ps1 -DeviceName "SC-ABC123" -WhatIf
    .\TagDevice.ps1 -DeviceName "SC-ABC123"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceName,
    [switch]$WhatIf
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users

# FIX 1: Removed Group.ReadWrite.All — not in the app registration and not needed.
# FIX 2: Added -UseDeviceCode to match automation script auth flow (avoids WAM/browser issues).
Connect-MgGraph -Scopes @(
    "Device.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All",
    "User.Read.All"
) -UseDeviceCode -NoWelcome

function Get-ExtensionAttribute10 {
    # FIX 3: SDK 2.x returns extensionAttributes as a typed property on the SDK object,
    # not in AdditionalProperties. Check both paths for compatibility across SDK versions.
    param ($Device)
    $val = $null
    if ($Device.ExtensionAttributes) {
        $val = $Device.ExtensionAttributes.ExtensionAttribute10
    }
    if (-not $val -and $Device.AdditionalProperties.extensionAttributes) {
        $val = $Device.AdditionalProperties.extensionAttributes.extensionAttribute10
    }
    return $val
}

try {
    # --- Step 1: Resolve device in Intune ---
    Write-Host "`nLooking up device in Intune: $DeviceName" -ForegroundColor Cyan

    $intuneDevices = Get-MgDeviceManagementManagedDevice `
        -Filter "deviceName eq '$DeviceName'" `
        -ErrorAction Stop

    if (-not $intuneDevices) {
        throw "Device '$DeviceName' not found in Intune."
    }

    # Take first result in case of duplicate names
    $intuneDevice = $intuneDevices | Select-Object -First 1
    Write-Host "Found in Intune — UserId: $($intuneDevice.UserId)" -ForegroundColor Yellow

    if (-not $intuneDevice.UserId) {
        throw "Device '$DeviceName' has no primary user assigned in Intune."
    }

    # --- Step 2: Resolve user's department ---
    Write-Host "`nLooking up user department..." -ForegroundColor Cyan

    $user = Get-MgUser `
        -UserId $intuneDevice.UserId `
        -Select "Id,DisplayName,Department,UserPrincipalName" `
        -ErrorAction Stop

    $user | Select-Object DisplayName, UserPrincipalName, Department | Format-List

    if ([string]::IsNullOrWhiteSpace($user.Department)) {
        throw "Department field is empty for user '$($user.DisplayName)'. Populate the Department field in Entra ID or AD first."
    }

    $department = $user.Department.Trim()
    Write-Host "Department: $department" -ForegroundColor Green

    # --- Step 3: Resolve device in Entra ID ---
    Write-Host "`nLooking up Entra ID device object..." -ForegroundColor Cyan

    # FIX 4: Include extensionAttributes in the initial $select so we can do a
    # skip-if-same check before writing — avoids unnecessary Graph write calls.
    $aadDevice = Get-MgDevice `
        -Filter "displayName eq '$DeviceName'" `
        -Select "id,displayName,extensionAttributes" `
        -ErrorAction Stop | Select-Object -First 1

    if (-not $aadDevice) {
        throw "Device '$DeviceName' not found in Entra ID. It may not be Azure AD joined."
    }

    Write-Host "Entra ID device: $($aadDevice.DisplayName) [$($aadDevice.Id)]" -ForegroundColor Yellow

    # --- Step 4: Skip if already correct ---
    $currentValue = Get-ExtensionAttribute10 -Device $aadDevice

    if ($currentValue -eq $department) {
        Write-Host "`n✓ Skipped — extensionAttribute10 is already '$department'" -ForegroundColor Green
        return
    }

    Write-Host "Current extensionAttribute10 : $(if ($currentValue) { $currentValue } else { '(not set)' })" -ForegroundColor Yellow
    Write-Host "Target value                 : $department" -ForegroundColor Yellow

    # --- Step 5: Write or WhatIf ---
    if ($WhatIf) {
        Write-Host "`nWhatIf: Would update extensionAttribute10 → '$department' on '$DeviceName'" -ForegroundColor Cyan
        return
    }

    Write-Host "`nUpdating extensionAttribute10..." -ForegroundColor Cyan

    $updatePayload = @{
        extensionAttributes = @{
            extensionAttribute10 = $department
        }
    }

    Update-MgDevice -DeviceId $aadDevice.Id -BodyParameter $updatePayload -ErrorAction Stop

    # Brief wait for Graph propagation
    Start-Sleep -Seconds 5

    # --- Step 6: Verify ---
    Write-Host "Verifying..." -ForegroundColor Cyan

    $verifyDevice = Get-MgDevice `
        -DeviceId $aadDevice.Id `
        -Select "displayName,id,extensionAttributes" `
        -ErrorAction Stop

    # FIX 5: Use the same helper that checks both SDK paths — this is why
    # verification was always showing "Update Status Unclear" before.
    $verifiedValue = Get-ExtensionAttribute10 -Device $verifyDevice

    Write-Host "`n=== Verification ===" -ForegroundColor Cyan
    Write-Host "Device : $($verifyDevice.DisplayName)"
    Write-Host "ID     : $($verifyDevice.Id)"

    if ($verifiedValue -eq $department) {
        Write-Host "`n✓ Success — extensionAttribute10 = '$verifiedValue'" -ForegroundColor Green
    } else {
        Write-Host "`n⚠ Verification unclear — expected '$department', got '$verifiedValue'" -ForegroundColor Yellow
        Write-Host "This can happen if Graph hasn't propagated yet. Wait 30 seconds and re-run with -WhatIf to check." -ForegroundColor Yellow
        Write-Host "`nRaw device JSON (for debugging):" -ForegroundColor DarkGray
        $verifyDevice | ConvertTo-Json -Depth 4
    }

    Write-Host "=====================" -ForegroundColor Cyan
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    Write-Error $_.Exception.StackTrace
}
