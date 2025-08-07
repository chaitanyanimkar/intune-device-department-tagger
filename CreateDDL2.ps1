param(
    [switch]$WhatIf
)

# Connect to Exchange Online if not already connected
Connect-ExchangeOnline

# Define the recipient filter
$previewFilter = "(RecipientType -eq 'UserMailbox') -and (Department -ne `$null) -and (UserAccountControl -ne 'AccountDisabled') -and (-not(RecipientTypeDetails -eq 'GuestMailUser')) -and (-not(RecipientTypeDetails -eq 'SharedMailbox'))"

# Preview members that would be included
Write-Host "Preview of members that would be included:" -ForegroundColor Green
$previewMembers = Get-Recipient -ResultSize Unlimited -Filter $previewFilter | 
    Select-Object DisplayName, PrimarySmtpAddress, Department, RecipientTypeDetails

$memberCount = $previewMembers.Count
$previewMembers | Format-Table

Write-Host "`nTotal inboxes that will be added to the dynamic list: $memberCount" -ForegroundColor Cyan

if (-not $WhatIf) {
    # Prompt for confirmation
    $confirmation = Read-Host "Do you want to create the dynamic distribution group? (Y/N)"
    if ($confirmation -eq 'Y') {
        # Create the dynamic distribution list
        New-DynamicDistributionGroup -Name "All-Active-Staff" `
            -DisplayName "All Active Staff" `
            -PrimarySmtpAddress "all-active-staff@<YOUR-COMPANY-DOMAIN>.com" ` # <---------- Change this to your domain 
            -RecipientFilter $previewFilter

        # Verify the group creation
        Write-Host "`nGroup details:" -ForegroundColor Green
        Get-DynamicDistributionGroup "All-Active-Staff" | Format-List Name, DisplayName, RecipientFilter, PrimarySmtpAddress

        # Show actual members
        Write-Host "`nCurrent group members:" -ForegroundColor Green
        Get-DynamicDistributionGroupMember "All-Active-Staff" | 
            Select-Object DisplayName, PrimarySmtpAddress, Department, RecipientTypeDetails
    }
} else {
    Write-Host "`nWhatIf mode: No changes made." -ForegroundColor Yellow
}
