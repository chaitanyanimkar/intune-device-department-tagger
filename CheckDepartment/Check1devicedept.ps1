# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All","DeviceManagementManagedDevices.Read.All" -NoWelcome

# Set the target device name to inspect
$deviceName = "YOUR-DEVICE-NAME"   # <-- replace with the actual device name

$intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$deviceName'"

if ($intuneDevice) {
    # Check user details including department and extensionAttribute10
    $myUser = Get-MgUser -UserId $intuneDevice.UserId -Select "Id,DisplayName,Department,JobTitle,extensionAttributes" -ErrorAction Stop

    Write-Host "User Details for: $($myUser.DisplayName)" -ForegroundColor Cyan
    $extAttr10 = $null
    if ($myUser.ExtensionAttributes) {
        $extAttr10 = $myUser.ExtensionAttributes.ExtensionAttribute10
    }
    $myUser | Select-Object DisplayName, Department, JobTitle
    Write-Host "ExtensionAttribute10: $extAttr10"
} else {
    Write-Host "Device not found: $deviceName" -ForegroundColor Red
}
