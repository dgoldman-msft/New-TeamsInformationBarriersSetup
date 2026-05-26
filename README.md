# TeamsInformationBarriersSetup

A PowerShell module that creates and configures an Information Barrier in a Microsoft 365 tenant.

## Module Layout

- `1.0/TeamsInformationBarriersSetup.psd1` versioned module manifest
- `1.0/TeamsInformationBarriersSetup.psm1` module loader
- `1.0/functions/New-TeamsInformationBarriersSetup.ps1` public function
- `1.0/internal/functions/` internal helper functions
- `docs/New-TeamsInformationBarriersSetup.md` command documentation

## Installation

Copy this repository into one of the paths in `$env:PSModulePath`, for example:

```text
C:\Users\<you>\Documents\PowerShell\Modules\TeamsInformationBarriersSetup\1.0\
```

Then import by name:

```powershell
Import-Module TeamsInformationBarriersSetup -Force
Get-Command -Module TeamsInformationBarriersSetup
```

You can also import the versioned manifest directly:

```powershell
Import-Module .\1.0\TeamsInformationBarriersSetup.psd1 -Force
```

## Examples

```powershell
New-TeamsInformationBarriersSetup -TenantName contoso.onmicrosoft.com -GuestNames user1@company.com, user2@company.com -Verbose
```

```powershell
New-TeamsInformationBarriersSetup -TenantName contoso.onmicrosoft.com -GuestNames user1@company.com, user2@company.com -WhatIf -Verbose
```

## Notes

- Required dependencies are installed when missing and when `ShouldProcess` allows it.
- `-TestUserPassword` accepts `SecureString`.
- `New-MgUser` requires a transient plaintext conversion for `-PasswordProfile`.

## Help

```powershell
Get-Help New-TeamsInformationBarriersSetup -Full
Get-Help New-TeamsInformationBarriersSetup -Examples
```
