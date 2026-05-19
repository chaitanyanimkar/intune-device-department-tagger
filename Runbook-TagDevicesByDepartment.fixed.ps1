<#
.SYNOPSIS
    Azure Automation Runbook — tags Intune Windows laptops with the primary
    user's department in extensionAttribute10.

.DESCRIPTION
    - Only processes devices whose names start with SCB-LPT or SCI-LPT.
    - Skips devices where extensionAttribute10 already matches the user's department.
    - Runs unattended via Azure Automation Managed Identity (no stored credentials).
    - Schedule recommended: every 2 hours for fast onboarding turnaround.

.NOTES
    Required Graph API app roles on the Automation Account Managed Identity:
        Device.ReadWrite.All
        DeviceManagementManagedDevices.Read.All
        User.Read.All

    To grant these, run Grant-RunbookPermissions.ps1 once from your local machine.

    --- FIX (vs. Runbook-TagDevicesByDepartment.ps1) ---
    Looks up the Entra device via deviceId (Intune's AzureAdDeviceId) instead
    of displayName. The displayName filter returned multiple records when an
    Entra device record duplicated, and Select-Object -First 1 picked one
    non-deterministically — causing extensionAttribute10 to flip between
    runs. deviceId is a unique GUID, so the lookup is now 1:1 even when
    duplicates exist transiently.
#>

[CmdletBinding()]
param(
    [bool]$WhatIf = $false
)

$DEVICE_PREFIXES = @("SCB-LPT", "SCI-LPT")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Output $line
}

function Get-ExtAttr10 {
    param($Device)
    $val = $null
    if ($Device.ExtensionAttributes) { $val = $Device.ExtensionAttributes.ExtensionAttribute10 }
    if (-not $val -and $Device.AdditionalProperties.extensionAttributes) { $val = $Device.AdditionalProperties.extensionAttributes.extensionAttribute10 }
    return $val
}

# ----- Auth -----
$isAzureAutomation = $null -ne $PSPrivateMetadata.JobId

if ($isAzureAutomation) {
    Write-Log "Running in Azure Automation — connecting via Managed Identity"
    Connect-MgGraph -Identity -NoWelcome
}
else {
    Write-Log "Running locally — connecting via stored DPAPI credentials"
    $configDir = "$env:APPDATA\SCGraphApp"
    $clientId = Get-Content "$configDir\clientId.txt"
    $tenantId = Get-Content "$configDir\tenantId.txt"
    $secret = Get-Content "$configDir\secret.txt" | ConvertTo-SecureString
    $credential = New-Object System.Management.Automation.PSCredential($clientId, $secret)
    Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome
}

Write-Log "Connected to Graph"

# ----- Fetch all Windows Intune devices -----
Write-Log "Fetching Windows devices from Intune..."
$allDevices = Get-MgDeviceManagementManagedDevice `
    -Filter "operatingSystem eq 'Windows'" -All `
    -ErrorAction Stop

$targetDevices = $allDevices | Where-Object {
    $name = $_.DeviceName
    $DEVICE_PREFIXES | Where-Object { $name -like "$_*" }
}

Write-Log "Total Windows devices in Intune : $($allDevices.Count)"
Write-Log "Matching SCB-LPT / SCI-LPT     : $($targetDevices.Count)"

# ----- Process each device -----
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($device in $targetDevices) {

    $result = [PSCustomObject]@{
        DeviceName    = $device.DeviceName
        UserName      = ""
        Department    = ""
        CurrentAttr10 = ""
        Status        = ""
    }

    if (-not $device.UserId) {
        $result.Status = "Skipped — no user assigned"
        $results.Add($result)
        continue
    }

    $user = Get-MgUser -UserId $device.UserId -Select "DisplayName,Department" -ErrorAction SilentlyContinue
    $result.UserName = $user.DisplayName

    if ([string]::IsNullOrWhiteSpace($user.Department)) {
        $result.Status = "Skipped — department not set for user"
        $results.Add($result)
        continue
    }

    $department = $user.Department.Trim()
    $result.Department = $department

    if (-not $device.AzureAdDeviceId) {
        $result.Status = "Skipped — Intune device missing AzureAdDeviceId"
        $results.Add($result)
        continue
    }

    $aadDevice = Get-MgDevice `
        -Filter "deviceId eq '$($device.AzureAdDeviceId)'" `
        -Select "id,displayName,extensionAttributes" `
        -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $aadDevice) {
        $result.Status = "Skipped — device not found in Entra ID"
        $results.Add($result)
        continue
    }

    $current = Get-ExtAttr10 -Device $aadDevice
    $result.CurrentAttr10 = $current

    if ($current -eq $department) {
        $result.Status = "Skipped — already correct"
        $results.Add($result)
        continue
    }

    if ($WhatIf) {
        $result.Status = "WhatIf — would update '$current' → '$department'"
        $results.Add($result)
        continue
    }

    try {
        Update-MgDevice -DeviceId $aadDevice.Id -BodyParameter @{
            extensionAttributes = @{ extensionAttribute10 = $department }
        } -ErrorAction Stop
        $result.Status = "Updated — '$current' → '$department'"
        Write-Log "$($device.DeviceName) : updated to '$department'"
    }
    catch {
        $result.Status = "Error — $($_.Exception.Message)"
        Write-Log "$($device.DeviceName) : ERROR — $($_.Exception.Message)" "ERROR"
    }

    $results.Add($result)
}

$updated = $results | Where-Object { $_.Status -like "Updated*" }
$skipped = $results | Where-Object { $_.Status -like "Skipped*" }
$errors = $results | Where-Object { $_.Status -like "Error*" }

Write-Log "------------------------------"
Write-Log "Updated  : $($updated.Count)"
Write-Log "Skipped  : $($skipped.Count)"
Write-Log "Errors   : $($errors.Count)"
Write-Log "------------------------------"

$results | ConvertTo-Csv -NoTypeInformation | Write-Output
