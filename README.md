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

## Information Barrier Configuration

This module creates the following three segments, keyed on `CustomAttribute1`:

| Segment | Filter | Purpose |
| --- | --- | --- |
| `SEG_A_GUESTS` | `CustomAttribute1 -eq 'Guest'` | External guest users |
| `SEG_B_INTERNAL_ALLOWED` | `CustomAttribute1 -eq 'Allowed'` | Internal users permitted to work with guests |
| `SEG_C_INTERNAL_OTHER` | `CustomAttribute1 -eq 'Other'` | Internal users isolated from guests |

### Default policy set (four policies)

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Block-Guest-To-Internal-Other` | SEG_A_GUESTS | Blocked | SEG_C_INTERNAL_OTHER |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Block-InternalOther-To-Guest` | SEG_C_INTERNAL_OTHER | Blocked | SEG_A_GUESTS |
| `Allow-InternalAllowed-To-Guest` | SEG_B_INTERNAL_ALLOWED | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |

**Resulting communication matrix (default):**

| | Guests (A) | Allowed (B) | Other (C) |
| --- | --- | --- | --- |
| **Guests (A)** | ✅ | ✅ | ❌ |
| **Allowed (B)** | ✅ | ✅ | ❌ |
| **Other (C)** | ❌ | ❌ | ✅ |

### Extended policy set — `-AllowInternalCommunication` (five policies)

When `-AllowInternalCommunication` is specified, two additional/replacement policies are created that allow `SEG_B_INTERNAL_ALLOWED` and `SEG_C_INTERNAL_OTHER` to communicate directly with each other.

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Block-Guest-To-Internal-Other` | SEG_A_GUESTS | Blocked | SEG_C_INTERNAL_OTHER |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Block-InternalOther-To-Guest` | SEG_C_INTERNAL_OTHER | Blocked | SEG_A_GUESTS |
| `Allow-InternalAllowed-To-All` | SEG_B_INTERNAL_ALLOWED | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED, SEG_C_INTERNAL_OTHER |
| `Allow-InternalOther-To-Allowed` | SEG_C_INTERNAL_OTHER | Allowed | SEG_B_INTERNAL_ALLOWED, SEG_C_INTERNAL_OTHER |

**Resulting communication matrix (`-AllowInternalCommunication`):**

| | Guests (A) | Allowed (B) | Other (C) |
| --- | --- | --- | --- |
| **Guests (A)** | ✅ | ✅ | ❌ |
| **Allowed (B)** | ✅ | ✅ | ✅ |
| **Other (C)** | ❌ | ✅ | ✅ |

### ⚠️ Risk: `-AllowInternalCommunication`

> **This switch weakens the data isolation that Information Barriers are designed to enforce. Carefully review the following risks before using it in a production tenant.**

**Indirect guest-to-Other exposure via shared spaces**
IB enforces isolation at the *direct communication* level (1:1 chat, search visibility). It does not prevent co-presence in a Teams channel or meeting. Because `SEG_B` can communicate with both `SEG_A` (guests) and `SEG_C` (Other), a `SEG_B` user can add both a guest and an `SEG_C` user to the same channel or meeting. In that shared space, guests and Other users are technically co-present even though they cannot communicate directly. This may violate regulatory or contractual data handling obligations that the default isolation is designed to satisfy.

**Compliance and regulatory impact**
If this configuration is used to satisfy a compliance requirement (e.g. data residency, insider risk, or contractual third-party isolation), enabling B-to-C communication may invalidate that compliance posture. Consult your compliance team before enabling this switch in a regulated environment.

**IB symmetry requirement**
Microsoft IB requires that communication permissions are symmetric: if segment X allows segment Y, segment Y must also allow segment X. The `-AllowInternalCommunication` code path creates both `Allow-InternalAllowed-To-All` and `Allow-InternalOther-To-Allowed` to satisfy this requirement. Manually editing only one side of a symmetric pair in the Microsoft Purview portal will result in a policy validation error when `Start-InformationBarrierPoliciesApplication` is run.

**Re-runs and stale policies**
This module uses an idempotent `Get-OrCreate` pattern. If you run once *without* `-AllowInternalCommunication` and then again *with* it (or vice versa), the **old policy names remain active** in the tenant alongside the new ones until you manually remove them from the Microsoft Purview compliance portal and re-apply. Mixed policy sets can produce unpredictable enforcement behaviour.

## Notes

- Required dependencies are installed when missing and when `ShouldProcess` allows it.
- `-TestUserPassword` accepts `SecureString`.
- `New-MgUser` requires a transient plaintext conversion for `-PasswordProfile`.

## Help

```powershell
Get-Help New-TeamsInformationBarriersSetup -Full
Get-Help New-TeamsInformationBarriersSetup -Examples
```
