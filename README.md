# Intune Device Department Tagger

PowerShell scripts that automatically sync the **department** field from each device owner's Entra ID (Azure AD) user account into the device's `extensionAttribute10` in Entra ID. This lets you create **dynamic device groups** in Intune or Entra ID that are scoped by department without any manual tagging.

---

## How it works

```
Intune managed device
       │
       ▼ UserId
Entra ID User ──► Department field
                        │
                        ▼
            extensionAttribute10 on the Entra ID device object
                        │
                        ▼
         Dynamic device group filter:
         (device.extensionAttribute10 -eq "Engineering")
```

1. The script fetches all Windows devices from Intune.
2. For each device it resolves the primary user's department from Entra ID.
3. If `extensionAttribute10` on the device already matches, it is skipped.
4. Otherwise the attribute is updated via the Microsoft Graph API.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| PowerShell 7+ | Or Windows PowerShell 5.1 |
| [Microsoft.Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation) | `Install-Module Microsoft.Graph` |
| Graph API **application** permissions | `Device.ReadWrite.All`, `DeviceManagementManagedDevices.Read.All`, `User.Read.All` |

Install the SDK:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

---

## Scripts

### `TagAllDevicesAutomation.ps1` — bulk tagger (main script)

Tags all Intune-enrolled Windows devices. Designed to run locally **or** as an Azure Automation runbook.

```powershell
# Dry-run (no changes made)
.\TagAllDevicesAutomation.ps1 -WhatIf

# Live run
.\TagAllDevicesAutomation.ps1

# Override the shared-device defaults
.\TagAllDevicesAutomation.ps1 -SharedDeviceNamePattern "KIOSK" -SharedDeviceDepartment "Kiosk-Devices"
```

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `-WhatIf` | `$false` | Report what would change without writing anything |
| `-SharedDeviceNamePattern` | `SHARED-PC` | Wildcard name pattern for shared/kiosk devices with no primary user |
| `-SharedDeviceDepartment` | `Shared-Devices` | Department tag applied to matched shared devices |

**Authentication**

- **Azure Automation**: the script detects the runbook environment automatically and connects via System-Assigned Managed Identity. Grant the Managed Identity the Graph API app roles listed above.
- **Local**: uses the device code flow (`https://microsoft.com/devicelogin`).

---

### `TagDevice.ps1` — single-device tagger

Tags one device by name. Useful for testing or on-demand tagging.

```powershell
# Dry-run
.\TagDevice.ps1 -DeviceName "DESKTOP-ABC123" -WhatIf

# Live
.\TagDevice.ps1 -DeviceName "DESKTOP-ABC123"
```

---

### `CheckDepartment\CheckallDepartments.ps1` — AD department audit

Reports which Active Directory users have the `Department` field populated and which do not. Exports results to a timestamped CSV.

```powershell
.\CheckDepartment\CheckallDepartments.ps1
```

> Requires the `ActiveDirectory` PowerShell module (RSAT or a domain controller).

---

### `CheckDepartment\Check1devicedept.ps1` — single-device inspector

Looks up one device's primary user and shows their department and current `extensionAttribute10` value. Edit `$deviceName` in the script before running.

```powershell
# Edit the script, set $deviceName = "YOUR-DEVICE-NAME", then:
.\CheckDepartment\Check1devicedept.ps1
```

---

## Typical workflow

1. **Audit first** — run `CheckallDepartments.ps1` to confirm that user `Department` fields are populated in AD/Entra ID.
2. **Dry-run** — run `TagAllDevicesAutomation.ps1 -WhatIf` and review the CSV output.
3. **Live run** — remove `-WhatIf` and let it update.
4. **Create dynamic groups** — in Entra ID / Intune, use a rule such as:
   ```
   (device.extensionAttribute10 -eq "Engineering")
   ```

---

## Output

The automation script outputs a CSV with one row per device:

| Column | Description |
|---|---|
| `DeviceName` | Intune device name |
| `UserName` | Display name of the primary user |
| `Department` | Department resolved for this device |
| `CurrentExtensionAttribute10` | Value before this run |
| `Status` | `Updated`, `Skipped - Already Set`, `WhatIf - Would Update`, `No Department Found or No User Assigned`, `Device Not Found in Azure AD`, or `Error: …` |
| `ProcessedDate` | Timestamp |

---

## License

MIT
