<#
.SYNOPSIS
    Azure Automation Runbook — tags Intune Windows laptops with the primary
    user's department in extensionAttribute10.

.DESCRIPTION
    - Only processes devices whose names start with SCB-LPT or SCI-LPT.
    - Skips devices where extensionAttribute10 already matches the user's department.
    - Runs unattended via Azure Automation Managed Identity (no stored credentials).
    - Schedule recommended: every 2 hours for fast onboarding turnaround.
    - Emits a ##RESULT_JSON## sentinel line at the end so the SCB IT Portal can
      parse a structured summary of modified devices.

.NOTES
    Required Graph API app roles on the Automation Account Managed Identity:
        Device.ReadWrite.All
        DeviceManagementManagedDevices.Read.All
        User.Read.All

    To grant these, run Grant-RunbookPermissions.ps1 once from your local machine.
#>

[CmdletBinding()]
param(
    [bool]$WhatIf = $false
)

$DEVICE_PREFIXES = @("SCB-LPT", "SCI-LPT")
#$TENANT_ID = "98f0543a-5a14-47f6-9d04-84909a8efe16"

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
# Azure Automation: Managed Identity (no credentials needed)
# Local/test: falls back to DPAPI files stored by Store-SCGraphCredentials.ps1

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

# Filter to SCB-LPT* and SCI-LPT* only
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

    # Skip if no user assigned
    if (-not $device.UserId) {
        $result.Status = "Skipped — no user assigned"
        $results.Add($result)
        continue
    }

    # Get user's department
    $user = Get-MgUser -UserId $device.UserId -Select "DisplayName,Department" -ErrorAction SilentlyContinue
    $result.UserName = $user.DisplayName

    if ([string]::IsNullOrWhiteSpace($user.Department)) {
        $result.Status = "Skipped — department not set for user"
        $results.Add($result)
        continue
    }

    $department = $user.Department.Trim()
    $result.Department = $department

    # Get Entra device object and current extensionAttribute10
    $aadDevice = Get-MgDevice `
        -Filter "displayName eq '$($device.DeviceName)'" `
        -Select "id,displayName,extensionAttributes" `
        -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $aadDevice) {
        $result.Status = "Skipped — device not found in Entra ID"
        $results.Add($result)
        continue
    }

    $current = Get-ExtAttr10 -Device $aadDevice
    $result.CurrentAttr10 = $current

    # Skip if already correct
    if ($current -eq $department) {
        $result.Status = "Skipped — already correct"
        $results.Add($result)
        continue
    }

    # WhatIf mode
    if ($WhatIf) {
        $result.Status = "WhatIf — would update '$current' → '$department'"
        $results.Add($result)
        continue
    }

    # Write extensionAttribute10
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

# ----- Summary -----
$updated         = $results | Where-Object { $_.Status -like "Updated*" }
$wouldUpdate     = $results | Where-Object { $_.Status -like "WhatIf*" }
$alreadyCorrect  = $results | Where-Object { $_.Status -eq "Skipped — already correct" }
$skippedNoUser   = $results | Where-Object { $_.Status -eq "Skipped — no user assigned" }
$skippedNoDept   = $results | Where-Object { $_.Status -eq "Skipped — department not set for user" }
$skippedNotEntra = $results | Where-Object { $_.Status -eq "Skipped — device not found in Entra ID" }
$errors          = $results | Where-Object { $_.Status -like "Error*" }

Write-Log "------------------------------"
Write-Log "Updated  : $($updated.Count)"
Write-Log "WhatIf   : $($wouldUpdate.Count)"
Write-Log "Skipped  : $(($alreadyCorrect.Count + $skippedNoUser.Count + $skippedNoDept.Count + $skippedNotEntra.Count))"
Write-Log "Errors   : $($errors.Count)"
Write-Log "------------------------------"

# Output CSV for Azure Automation job logs
$results | ConvertTo-Csv -NoTypeInformation | Write-Output

# ----- Structured result for portal consumption -----
# Portal scans output for the ##RESULT_JSON## marker and parses the JSON that follows.
$modifiedSource = if ($WhatIf) { $wouldUpdate } else { $updated }
$resultPayload = [ordered]@{
    mode   = if ($WhatIf) { "whatif" } else { "live" }
    totals = [ordered]@{
        scanned           = $targetDevices.Count
        updated           = $updated.Count
        wouldUpdate       = $wouldUpdate.Count
        alreadyCorrect    = $alreadyCorrect.Count
        skippedNoUser     = $skippedNoUser.Count
        skippedNoDept     = $skippedNoDept.Count
        skippedNotInEntra = $skippedNotEntra.Count
        errors            = $errors.Count
    }
    modified = @($modifiedSource | ForEach-Object {
        [ordered]@{
            deviceName = $_.DeviceName
            userName   = $_.UserName
            department = $_.Department
            previous   = $_.CurrentAttr10
        }
    })
    errorDetails = @($errors | ForEach-Object {
        [ordered]@{
            deviceName = $_.DeviceName
            message    = $_.Status
        }
    })
}
Write-Output ("##RESULT_JSON## " + ($resultPayload | ConvertTo-Json -Compress -Depth 5))
