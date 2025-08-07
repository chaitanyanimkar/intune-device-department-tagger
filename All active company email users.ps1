# filepath: c:\Users\cnimkar\Downloads\DDL-Drizzy\All_active_company_email_users.ps1

#Requires -Modules Microsoft.Graph
#Requires -Version 7.0

# Connect to Microsoft Graph with the required permissions
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"
}

# Group ID configuration
$groupId = "39e28382-2772-4569-947f-ff3bf999602b"

try {
    # Get group details
    $groupInfo = Get-MgGroup -GroupId $groupId
    
    # Get group members
    $groupMembers = Get-MgGroupMember -GroupId $groupId
    $userDetails = foreach ($member in $groupMembers) {
        Get-MgUser -UserId $member.Id | 
            Select-Object DisplayName, UserPrincipalName, Mail
    }

    # Display group info
    Write-Host "`nGroup Details:" -ForegroundColor Cyan
    $groupInfo | Select-Object DisplayName, Description, SecurityEnabled, MailEnabled

    # Display members
    Write-Host "`nGroup Members:" -ForegroundColor Cyan
    $userDetails | Format-Table
} 
catch {
    Write-Error "Error accessing group: $($_.Exception.Message)"
}