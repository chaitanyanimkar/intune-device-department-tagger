# DDL-Drizzy

This repository contains PowerShell scripts for managing Exchange Online dynamic distribution lists and user mailboxes at StructureCraft. These scripts help automate the process of previewing, creating, and managing dynamic distribution groups based on user attributes.

## Scripts

- **CreateDDL2.ps1**: Previews and creates a dynamic distribution group (DDL) for all active staff mailboxes with a department set, excluding guests and shared mailboxes. Includes a WhatIf mode for safe previewing.
- **CreateDDL.ps1**: (Legacy/alternate version) Script for creating dynamic distribution lists.
- **All active company email users.ps1**: Script to list all active company email users.
- **All_DDL_Present_In_Tenant.ps1**: Script to list all dynamic distribution lists present in the tenant.

## CSV Files

- **AllActiveStaff_Members.csv** / **AllActiveStaffMembers.csv**: Example output files containing lists of active staff members.

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

## Getting Started with GitHub

1. [Create a GitHub account](https://github.com/join) if you don’t have one.
2. [Create a new repository](https://github.com/new) and upload your files.
3. Clone your repo locally:
   ```powershell
   git clone https://github.com/your-username/your-repo.git
   ```
4. Add your files, commit, and push:
   ```powershell
   git add .
   git commit -m "Initial commit"
   git push origin main
   ```

## Resources
- [GitHub Docs: Hello World](https://docs.github.com/en/get-started/quickstart/hello-world)
- [How to contribute to open source](https://opensource.guide/how-to-contribute/)

---

Feel free to update this README as your project evolves!
