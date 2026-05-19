[CmdletBinding()]
param(
    [switch]$WhatIf,

    # Pattern used to identify shared/kiosk devices that have no primary user assigned.
    # Devices whose names match this wildcard pattern will be tagged with $SharedDeviceDepartment
    # instead of looking up the primary user's department.
    # Set to $null or an empty string to disable this special-case logic.
    [string]$SharedDeviceNamePattern = "SHARED-PC",

    # Department tag applied to devices that match $SharedDeviceNamePattern.
    [string]$SharedDeviceDepartment  = "Shared-Devices"
)

# Required Microsoft Graph app roles (Application permissions — not delegated):
#   Device.ReadWrite.All
#   DeviceManagementManagedDevices.Read.All
#   User.Read.All

function Get-DeviceOwnerDepartment {
    param ([string]$DeviceName, [string]$UserId)
    if (-not $UserId) { return $null }
    $user = Get-MgUser -UserId $UserId -Select "DisplayName,Department" -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($user.Department)) { return $null }
    return $user.Department
}

function Update-DeviceDepartment {
    param (
        [string]$DeviceId,
        [string]$Department
    )
    $updatePayload = @{
        extensionAttributes = @{
            extensionAttribute10 = $Department
        }
    }
    Update-MgDevice -DeviceId $DeviceId -BodyParameter $updatePayload -ErrorAction Stop
}

try {
    # Detect Azure Automation by the presence of the job metadata variable
    $isAzureAutomation = $null -ne $PSPrivateMetadata.JobId

    if ($isAzureAutomation) {
        # Managed Identity — enable System-Assigned Managed Identity on the Automation
        # account and grant it the Graph API app roles listed above.
        Write-Output "Running in Azure Automation — connecting via Managed Identity..."
        Connect-MgGraph -Identity -NoWelcome
    } else {
        # Device code flow — avoids WAM/browser issues on some machines.
        # A code will be printed; open https://microsoft.com/devicelogin and enter it.
        Write-Host "Running locally — follow the device code prompt to sign in..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes "Device.ReadWrite.All","DeviceManagementManagedDevices.Read.All","User.Read.All" -UseDeviceCode -NoWelcome
    }

    $results = @()

    Write-Host "Fetching Windows devices from Intune..." -ForegroundColor Cyan
    $intuneDevices = Get-MgDeviceManagementManagedDevice -Filter "operatingSystem eq 'Windows'" -All
    Write-Host "`nFound $($intuneDevices.Count) Windows devices" -ForegroundColor Yellow

    foreach ($device in $intuneDevices) {
        Write-Host "`nProcessing device: $($device.DeviceName)" -ForegroundColor Cyan
        $department = $null

        # Tag shared/kiosk devices that match the configured name pattern.
        # These devices typically have no primary user, so department lookup would fail.
        if ($SharedDeviceNamePattern -and $device.DeviceName -like "*$SharedDeviceNamePattern*") {
            $department = $SharedDeviceDepartment
        } elseif ($device.UserId) {
            $department = Get-DeviceOwnerDepartment -DeviceName $device.DeviceName -UserId $device.UserId
        }

        $aadDevice = (Get-MgDevice -Filter "displayName eq '$($device.DeviceName)'" -Select "id,displayName,extensionAttributes" -ErrorAction SilentlyContinue) | Select-Object -First 1
        $currentE10 = $null
        if ($aadDevice) {
            if ($aadDevice.ExtensionAttributes) {
                $currentE10 = $aadDevice.ExtensionAttributes.ExtensionAttribute10
            }
            if (-not $currentE10 -and $aadDevice.AdditionalProperties.extensionAttributes) {
                $currentE10 = $aadDevice.AdditionalProperties.extensionAttributes.extensionAttribute10
            }
        }

        $resultObj = [PSCustomObject]@{
            DeviceName                 = $device.DeviceName
            UserName                   = if ($device.UserId) { (Get-MgUser -UserId $device.UserId -Select DisplayName).DisplayName } else { "" }
            Department                 = $department
            CurrentExtensionAttribute10 = $currentE10
            Status                     = ""
            ProcessedDate              = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        if (-not $aadDevice) {
            $resultObj.Status = "Device Not Found in Azure AD"
            $results += $resultObj
            continue
        }

        Write-Host "AAD Device found: $($aadDevice.DisplayName) [$($aadDevice.Id)]" -ForegroundColor Yellow

        if (-not $department) {
            $resultObj.Status = "No Department Found or No User Assigned"
            $results += $resultObj
            continue
        }

        if ($currentE10 -eq $department) {
            $resultObj.Status = "Skipped - Already Set"
            $results += $resultObj
            continue
        }

        if ($WhatIf) {
            $resultObj.Status = "WhatIf - Would Update"
            $results += $resultObj
            continue
        }

        try {
            Update-DeviceDepartment -DeviceId $aadDevice.Id -Department $department
            $resultObj.Status = "Updated"
        } catch {
            $resultObj.Status = "Error: $_"
        }
        $results += $resultObj
    }

    # Output results as CSV to the job output stream
    $csvContent = $results | ConvertTo-Csv -NoTypeInformation | Out-String
    Write-Output "Device Department Update Results (CSV):"
    Write-Output $csvContent
}
catch {
    Write-Error "Error: $_"
}
