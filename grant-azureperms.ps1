# Connect using your stored credentials
$configDir = "$env:APPDATA\SCGraphApp"
$clientId = Get-Content "$configDir\clientId.txt"
$tenantId = Get-Content "$configDir\tenantId.txt"
$secret = Get-Content "$configDir\secret.txt" | ConvertTo-SecureString
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secret)
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

$managedIdentityObjectId = "8e674300-8375-4c55-b2d6-1c5f47a1cddb"
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

@("Device.ReadWrite.All", "DeviceManagementManagedDevices.Read.All", "User.Read.All") | ForEach-Object {
    $roleName = $_
    $appRole = $graphSP.AppRoles | Where-Object { $_.Value -eq $roleName -and $_.AllowedMemberTypes -contains "Application" }
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $managedIdentityObjectId `
        -PrincipalId        $managedIdentityObjectId `
        -ResourceId         $graphSP.Id `
        -AppRoleId          $appRole.Id | Out-Null
    Write-Host "Granted: $roleName" -ForegroundColor Green
}