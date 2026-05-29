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
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames guest1@fabrikam.com,guest2@fabrikam.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases OtherUser1,OtherUser2 `
    -SkipProvisioningWait
```

```powershell
# Dry run — no changes made
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames guest1@fabrikam.com,guest2@fabrikam.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases OtherUser1,OtherUser2 `
    -WhatIf -Verbose
```

```powershell
# Enforce one external domain per team
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames guest1@fabrikam.com,guest1@litware.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases OtherUser1,OtherUser2 `
    -IsolateGuestDomains `
    -SkipProvisioningWait
```

## Information Barrier Configuration

Microsoft Purview enforces **one policy per segment**. An Allow policy implicitly blocks all
segments not listed as targets — no separate Block policy is needed on the same segment.

### Segments

**Default:** three segments keyed on `CustomAttribute1`:

| Segment | Filter | Purpose |
| --- | --- | --- |
| `SEG_A_GUESTS` | `CustomAttribute1 -eq 'Guest'` | External guest users |
| `SEG_B_INTERNAL_ALLOWED` | `CustomAttribute1 -eq 'Allowed'` | Internal users permitted to work with guests |
| `SEG_C_INTERNAL_OTHER` | `CustomAttribute1 -eq 'Other'` | Internal users isolated from guests |

**With `-IsolateGuestDomains`:** one segment per unique guest domain (`SEG_A_GUESTS` is not created):

| Segment | Filter | Purpose |
| --- | --- | --- |
| `SEG_GUEST_<DOMAIN>` | `CustomAttribute1 -eq 'Guest_<domain>'` | Guests from a specific external domain |
| `SEG_B_INTERNAL_ALLOWED` | `CustomAttribute1 -eq 'Allowed'` | Internal users permitted to work with guests |
| `SEG_C_INTERNAL_OTHER` | `CustomAttribute1 -eq 'Other'` | Internal users isolated from guests |

### Default policy set (three policies — one per segment)

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Allow-InternalAllowed-To-Guest` | SEG_B_INTERNAL_ALLOWED | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Block-InternalOther-To-Guest` | SEG_C_INTERNAL_OTHER | Blocked | SEG_A_GUESTS |

**Resulting communication matrix (default):**

| | Guests (A) | Allowed (B) | Other (C) |
| --- | --- | --- | --- |
| **Guests (A)** | ✅ | ✅ | ❌ |
| **Allowed (B)** | ✅ | ✅ | ❌ |
| **Other (C)** | ❌ | ❌ | ✅ |

### Extended policy set — `-AllowInternalCommunication` (three policies — one per segment)

Adds direct communication between `SEG_B_INTERNAL_ALLOWED` and `SEG_C_INTERNAL_OTHER`.

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
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
IB enforces isolation at the *direct communication* level (1:1 chat, search visibility). It does not prevent co-presence in a Teams channel or meeting. Because `SEG_B` can communicate with both `SEG_A` (guests) and `SEG_C` (Other), a `SEG_B` user can add both a guest and an `SEG_C` user to the same channel or meeting. In that shared space, guests and Other users are technically co-present even though they cannot communicate directly.

**Compliance and regulatory impact**
If this configuration is used to satisfy a compliance requirement (e.g. data residency, insider risk, or contractual third-party isolation), enabling B-to-C communication may invalidate that compliance posture. Consult your compliance team before enabling this switch in a regulated environment.

### Per-domain guest isolation — `-IsolateGuestDomains` (N+2 policies — one per segment)

Each unique external guest domain gets its own segment and one Allow policy. Guests from
different external domains are implicitly blocked from each other — no separate Block policy
required. Satisfies a strict one-external-domain-per-team rule.

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Allow-SEG_GUEST_DOMAIN-To-Team` | SEG_GUEST_DOMAIN | Allowed | SEG_GUEST_DOMAIN, SEG_B_INTERNAL_ALLOWED |
| `Allow-InternalAllowed-To-AllGuests` | SEG_B_INTERNAL_ALLOWED | Allowed | all SEG_GUEST_* + SEG_B_INTERNAL_ALLOWED |
| `Allow-InternalOther-To-Allowed` | SEG_C_INTERNAL_OTHER | Allowed | SEG_B_INTERNAL_ALLOWED, SEG_C_INTERNAL_OTHER |

**Re-runs and stale policies**
This module uses an idempotent `Get-OrCreate` pattern. If you switch between modes (e.g. run
once without `-IsolateGuestDomains` and then again with it), the **old policy names remain active**
in the tenant until you manually remove them from the Microsoft Purview compliance portal and
re-apply. Mixed policy sets can produce unpredictable enforcement behaviour.

## Notes

- Required dependencies are installed automatically from PSGallery when missing and when `ShouldProcess` allows it.
- `-TestUserPassword` accepts `SecureString`. If neither `-Password` nor `-TestUserPassword` is supplied, the command prompts interactively.
- `New-MgUser` requires a transient plaintext conversion for `-PasswordProfile`.
- Scoped directory search must be enabled in the Teams admin center before IB policies take effect. Wait at least a few hours after enabling.
- Teams groups created before IB was enabled are in Open mode. Update them to Implicit mode using the [Microsoft mode-update script](https://learn.microsoft.com/en-us/purview/information-barriers-teams-powershell-script) after running.
- IB policies do NOT apply to federated external users — only to B2B guests invited via Microsoft Entra.

## Help

```powershell
Get-Help New-TeamsInformationBarriersSetup -Full
Get-Help New-TeamsInformationBarriersSetup -Examples
```
