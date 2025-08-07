# Connect to Exchange Online if not already connected
Connect-ExchangeOnline

# Define the recipient filter
$previewFilter = @"
(RecipientType -eq 'UserMailbox') -and 
((EmailAddresses -like 'smtp:*@structurecraft.com') -or (EmailAddresses -like 'smtp:*@dowellam.com')) -and 
(Department -ne `$null) -and 
(UserAccountControl -ne 'AccountDisabled') -and 
(-not(CustomAttribute1 -eq 'Contractor')) -and 
(-not(CustomAttribute1 -eq 'ServiceAccount'))
"@

# Preview members that would be included
Write-Host "Preview of members that would be included:" -ForegroundColor Green
Get-Recipient -ResultSize Unlimited -Filter $previewFilter | 
    Select-Object DisplayName, PrimarySmtpAddress, Department

# Prompt for confirmation
$confirmation = Read-Host "Do you want to create the dynamic distribution group? (Y/N)"
if ($confirmation -eq 'Y') {
    # Create the dynamic distribution list
    New-DynamicDistributionGroup -Name "All-Active-Staff" `
        -DisplayName "All Active Staff" `
        -PrimarySmtpAddress "all-active-staff@structurecraft.com" `
        -RecipientFilter $previewFilter `
        -HiddenFromAddressListsEnabled $false

    # Verify the group creation
    Write-Host "`nGroup details:" -ForegroundColor Green
    Get-DynamicDistributionGroup "All-Active-Staff" | Format-List Name, DisplayName, RecipientFilter, PrimarySmtpAddress

    # Show actual members
    Write-Host "`nCurrent group members:" -ForegroundColor Green
    Get-DynamicDistributionGroupMember "All-Active-Staff" | 
        Select-Object DisplayName, PrimarySmtpAddress, Department
}