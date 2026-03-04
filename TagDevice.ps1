param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceName,
    [switch]$WhatIf
)

# Add required scope for group management
Connect-MgGraph -Scopes @(
    "Device.ReadWrite.All",
    "User.Read.All",
    "Group.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All"
) -NoWelcome

try {
    # Get the device from Intune first
    Write-Host "`nGetting device from Intune..." -ForegroundColor Cyan
    $intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'" -ErrorAction Stop
    Write-Host "Intune Device UserId: $($intuneDevice.UserId)" -ForegroundColor Yellow

    # Get user details with explicit Select
    Write-Host "`nGetting user details..." -ForegroundColor Cyan
    $user = Get-MgUser -UserId $intuneDevice.UserId -Select "Id,DisplayName,Department,UserPrincipalName" -ErrorAction Stop
    
    Write-Host "User details:" -ForegroundColor Yellow
    $user | Select-Object DisplayName, Department, UserPrincipalName | Format-List

    $department = $user.Department

    if ([string]::IsNullOrEmpty($department)) {
        throw "Department not found for user: $($user.DisplayName)"
    }

    Write-Host "Department found: $department" -ForegroundColor Green

    # Get Azure AD device with properties
    $aadDevice = (Get-MgDevice -Filter "displayName eq '$DeviceName'" -ErrorAction Stop) | Select-Object -First 1
    
    # Build the update payload correctly
    $updatePayload = @{
        extensionAttributes = @{
            extensionAttribute10 = $department
        }
    }
    
    if (-not $WhatIf) {
        # Update device with properties
        Write-Host "`nUpdating device attributes..." -ForegroundColor Cyan
        Update-MgDevice -DeviceId $aadDevice.Id -BodyParameter $updatePayload
        
        # Wait for update to process
        Write-Host "Waiting for update to process..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        # Clear verification check
        Write-Host "`n=== Verification Results ===" -ForegroundColor Cyan
        
        # Get latest device data
        $verifyDevice = Get-MgDevice -DeviceId $aadDevice.Id -Select "displayName,id,extensionAttributes" -ErrorAction Stop
        
        # Display basic device info
        Write-Host "`nDevice Information:" -ForegroundColor Green
        Write-Host "Name: $($verifyDevice.DisplayName)"
        Write-Host "ID: $($verifyDevice.Id)"
        
        # Check if update was successful
        $attributes = $verifyDevice.AdditionalProperties.extensionAttributes
        
        if ($null -ne $attributes -and $attributes.extensionAttribute10 -eq $department) {
            Write-Host "`n✓ Update Successful!" -ForegroundColor Green
            Write-Host "ExtensionAttribute10 = $($attributes.extensionAttribute10)"
            Write-Host "Matches Department: $department"
        } else {
            Write-Host "`n⚠ Update Status Unclear" -ForegroundColor Yellow
            Write-Host "`nDebug Information:" -ForegroundColor Yellow
            Write-Host "Expected Department: $department"
            Write-Host "Raw Device Data:" 
            $verifyDevice | ConvertTo-Json -Depth 3
        }
        
        Write-Host "`n=== End Verification ===" -ForegroundColor Cyan
    } else {
        Write-Host "`nWhatIf: Would tag device '$DeviceName' with department '$department' in extensionAttribute10" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Error: $_"
    Write-Error $_.Exception.StackTrace
}