<#
.SYNOPSIS
    One-time setup: stores Graph app credentials as DPAPI-encrypted files.
    PS7-compatible — no CredentialManager module needed.
    Encrypted to your Windows user account — only you can decrypt on this machine.
#>

$configDir = "$env:APPDATA\SCGraphApp"
$null = New-Item -Path $configDir -ItemType Directory -Force

Write-Host "SC Graph Credential Setup" -ForegroundColor Cyan
Write-Host "=========================`n" -ForegroundColor Cyan

$clientId = Read-Host "Paste your App (Client) ID"
$tenantId = "98f0543a-5a14-47f6-9d04-84909a8efe16"
$secret   = Read-Host "Paste your Client Secret" -AsSecureString

# Store clientId and tenantId as plain text (not sensitive)
$clientId | Set-Content "$configDir\clientId.txt"
$tenantId | Set-Content "$configDir\tenantId.txt"

# Store secret as DPAPI-encrypted string (only decryptable by this user on this machine)
$secret | ConvertFrom-SecureString | Set-Content "$configDir\secret.txt"

Write-Host "`n✓ Credentials saved to $configDir" -ForegroundColor Green
Write-Host "All Graph scripts will now connect silently." -ForegroundColor Green
