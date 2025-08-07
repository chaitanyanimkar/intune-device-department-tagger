# Connect to Exchange Online if not already connected
Connect-ExchangeOnline

# Get all Dynamic Distribution Groups
$ddls = Get-DynamicDistributionGroup

foreach ($ddl in $ddls) {
    Write-Host "`nGroup: $($ddl.DisplayName) ($($ddl.Name))" -ForegroundColor Cyan
    try {
        $members = Get-DynamicDistributionGroupMember -Identity $ddl.Identity
        if ($members) {
            $members | Select-Object @{Name="Group";Expression={$ddl.DisplayName}}, DisplayName, PrimarySmtpAddress, Department, RecipientTypeDetails | Format-Table -AutoSize
        } else {
            Write-Host "No members found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Could not retrieve members for $($ddl.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Optional: Export all members of all DDLs to a CSV
# $allMembers = foreach ($ddl in $ddls) {
#     Get-DynamicDistributionGroupMember -Identity $ddl.Identity | 
#         Select-Object @{Name="Group";Expression={$ddl.DisplayName}}, DisplayName, PrimarySmtpAddress, Department, RecipientTypeDetails
# }
# $allMembers | Export-Csv ".\AllDDL_Members.csv" -NoTypeInformation


# Connect to Exchange Online if not already connected
Connect-ExchangeOnline

# Get members of the specific DDL
$members = Get-DynamicDistributionGroupMember -Identity "All-Active-Staff" |
    Select-Object DisplayName, PrimarySmtpAddress, Department, RecipientTypeDetails

# Output to console (optional)
$members | Format-Table -AutoSize

# Export to CSV
$members | Export-Csv ".\AllActiveStaff_Members.csv" -NoTypeInformation