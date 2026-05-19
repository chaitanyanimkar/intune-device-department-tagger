# Prerequisites:
# Run Store-SCGraphCredentials.ps1 once before using this script.
# App registration needs: Device.ReadWrite.All, DeviceManagementManagedDevices.Read.All, User.Read.All

param(
    [Parameter(Mandatory)]
    [string]$DeviceName
)

# Step 1 — Connect silently via DPAPI-encrypted credentials
$configDir = "$env:APPDATA\SCGraphApp"

$clientId = Get-Content "$configDir\clientId.txt"
$tenantId = Get-Content "$configDir\tenantId.txt"
$secret   = Get-Content "$configDir\secret.txt" | ConvertTo-SecureString

$credential = New-Object System.Management.Automation.PSCredential($clientId, $secret)
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

Write-Host "Connected to Graph (silent)" -ForegroundColor DarkGray

# Step 2 — Get device from Intune, pull the assigned user ID
$intuneDevice = Get-MgDeviceManagementManagedDevice -All |
    Where-Object { $_.DeviceName -ieq $DeviceName } |
    Select-Object -First 1

if (-not $intuneDevice) { throw "Device not found in Intune: $DeviceName" }
if (-not $intuneDevice.UserId) { throw "No user assigned to this device in Intune" }

# Step 3 — Get that user's department from Entra ID
$user = Get-MgUser -UserId $intuneDevice.UserId -Select "DisplayName,Department"

if ([string]::IsNullOrWhiteSpace($user.Department)) {
    throw "Department not set for user: $($user.DisplayName)"
}

Write-Host "User: $($user.DisplayName) | Department: $($user.Department)"

# Step 4 — Find the Entra device object and write extensionAttribute10
$device = Get-MgDevice -Filter "displayName eq '$DeviceName'" | Select-Object -First 1

if (-not $device) { throw "Device not found in Entra ID: $DeviceName" }

Update-MgDevice -DeviceId $device.Id -BodyParameter @{
    extensionAttributes = @{
        extensionAttribute10 = $user.Department
    }
}

Write-Host "Done — extensionAttribute10 set to '$($user.Department)' on $DeviceName" -ForegroundColor Green

