# Create-DLL-ExchangeOnline

This repository contains PowerShell scripts for managing Exchange Online dynamic distribution lists and user mailboxes. These scripts help automate the process of previewing, creating, and managing dynamic distribution groups based on user attributes mainly Department.

## Scripts

- **CreateDDL2.ps1**: Previews and creates a dynamic distribution group (DDL) for all active staff mailboxes with a department set, excluding guests and shared mailboxes. Includes a WhatIf mode for safe previewing.
- **CreateDDL.ps1**: (Legacy/alternate version) Script for creating dynamic distribution lists.
- **All active company email users.ps1**: Script to list all active company email users.
- **All_DDL_Present_In_Tenant.ps1**: Script to list all dynamic distribution lists present in the tenant.

## Usage

1. Open PowerShell and connect to Exchange Online:
   ```powershell
   Connect-ExchangeOnline
   ```
2. Run the desired script. For example:
   ```powershell
   .\CreateDDL2.ps1
   ```
   Use the `-WhatIf` switch to preview changes without making them:
   ```powershell
   .\CreateDDL2.ps1 -WhatIf
   ```

## Contributing

Contributions are welcome! Please fork the repository, make your changes, and submit a pull request. For major changes, open an issue first to discuss what you would like to change.


## Resources
- [How to contribute to open source](https://opensource.guide/how-to-contribute/)

---
