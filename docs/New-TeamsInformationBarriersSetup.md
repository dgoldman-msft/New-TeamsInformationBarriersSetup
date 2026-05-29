---
external help file: TeamsInformationBarriersSetup-help.xml
Module Name: TeamsInformationBarriersSetup
online version: https://github.com/microsoft/TeamsInformationBarriersSetup
schema: 2.0.0
---

# New-TeamsInformationBarriersSetup

## SYNOPSIS

Builds a repeatable Information Barrier lab configuration for Teams in Microsoft 365.

## SYNTAX

```powershell
New-TeamsInformationBarriersSetup
    -UserPrincipalName <String>
    -AllowedInternalAliases <String[]>
    -OtherInternalAliases <String[]>
    -GuestNames <String[]>
    [-TestUserPassword <SecureString>]
    [-Password <String>]
    [-IbAllowGroupDisplayName <String>]
    [-AttrGuest <String>]
    [-AttrAllowed <String>]
    [-AttrOther <String>]
    [-LogDirectory <String>]
    [-ShowBanner <Boolean>]
    [-StayConnected]
    [-SkipProvisioningWait]
    [-AllowInternalCommunication]
    [-IsolateGuestDomains]
    [-WhatIf]
    [-Confirm]
    [<CommonParameters>]
```

## DESCRIPTION

`New-TeamsInformationBarriersSetup` automates end-to-end setup of a Microsoft Teams Information
Barriers (IB) configuration in a Microsoft 365 tenant. It is designed to be re-runnable:
existing users, groups, segments, and policies are detected and reused when present.

### Phase 0 — Identity (Microsoft Graph)

- Looks up or creates internal test users in the *Allowed* and *Other* categories
- Creates or reuses an Entra security group (`IB-Allow-Team`) for the allowed users
- Invites external guests via the Graph invitation API

### Phase 1 — Exchange Online

- Connects to Exchange Online (unless `-StayConnected` is specified)
- Polls until each internal user appears as a **Mailbox** (licensed) or **MailUser** (unlicensed)
  object in EXO — both types support `CustomAttribute1` and IB segments
- Connects to Security and Compliance PowerShell

### Phase 2 — Recipient tagging

- Stamps `CustomAttribute1` on each mailbox (`Set-Mailbox`) or mail user (`Set-MailUser`)
  with the value `Allowed`, `Other`, or `Guest`
- IB segments key on this attribute

### Phase 3 — Segments

**Default:** creates three organization segments:

| Segment | Filter |
| --- | --- |
| `SEG_A_GUESTS` | `CustomAttribute1 -eq 'Guest'` |
| `SEG_B_INTERNAL_ALLOWED` | `CustomAttribute1 -eq 'Allowed'` |
| `SEG_C_INTERNAL_OTHER` | `CustomAttribute1 -eq 'Other'` |

**With `-IsolateGuestDomains`:** one segment per unique guest domain plus SEG_B and SEG_C
(`SEG_A_GUESTS` is not created):

| Segment | Filter |
| --- | --- |
| `SEG_GUEST_<DOMAIN>` | `CustomAttribute1 -eq 'Guest_<domain>'` |
| `SEG_B_INTERNAL_ALLOWED` | `CustomAttribute1 -eq 'Allowed'` |
| `SEG_C_INTERNAL_OTHER` | `CustomAttribute1 -eq 'Other'` |

### Phase 4 — Policies and enforcement

Microsoft Purview enforces **one policy per segment**. An Allow policy implicitly blocks all
segments not listed as targets — no separate Block policy is needed on the same segment.

**Default** (three IB policies — one per segment):

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Allow-InternalAllowed-To-Guest` | SEG_B_INTERNAL_ALLOWED | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Block-InternalOther-To-Guest` | SEG_C_INTERNAL_OTHER | Blocked | SEG_A_GUESTS |

**With `-AllowInternalCommunication`** (three IB policies — one per segment):

| Policy | AssignedSegment | Mode | Targets |
| --- | --- | --- | --- |
| `Allow-Guest-To-Team` | SEG_A_GUESTS | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED |
| `Allow-InternalAllowed-To-All` | SEG_B_INTERNAL_ALLOWED | Allowed | SEG_A_GUESTS, SEG_B_INTERNAL_ALLOWED, SEG_C_INTERNAL_OTHER |
| `Allow-InternalOther-To-Allowed` | SEG_C_INTERNAL_OTHER | Allowed | SEG_B_INTERNAL_ALLOWED, SEG_C_INTERNAL_OTHER |

**With `-IsolateGuestDomains`** (N+2 policies, one per segment, where N = unique guest domains):
One `Allow-SEG_GUEST_<DOMAIN>-To-Team` policy per domain segment, one policy for SEG_B
(`Allow-InternalAllowed-To-AllGuests`), and one for SEG_C (`Allow-InternalOther-To-Allowed`).
Each domain segment is restricted to itself and SEG_B — guests from different domains are
implicitly blocked from each other.

Calls `Start-InformationBarrierPoliciesApplication` to begin enforcement.

A timestamped log file is written to `-LogDirectory` on every run.

## EXAMPLES

### Example 1: Basic setup with pre-licensed users

```powershell
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -SkipProvisioningWait
```

Sets up the full IB lab using four pre-licensed internal users: `AllowedUser1` and `AllowedUser2`
in the Allowed segment (permitted to communicate with guests), `InternalUserName1` and
`InternalUserName2` in the Other segment (blocked from guests). Two external guests are invited.
`-SkipProvisioningWait` is used because all internal users already have Exchange Online mailboxes.

### Example 2: Re-run using an existing Exchange Online session

```powershell
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -StayConnected `
    -SkipProvisioningWait
```

Re-runs setup using an existing Exchange Online session. Use this after a partial failure or
once Exchange Online licenses have been assigned to any newly created users.

### Example 3: Dry run

```powershell
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -WhatIf -Verbose
```

Simulates all actions without making changes and prints verbose progress to the console.

### Example 4: Pre-supplied SecureString password

```powershell
$pw = Read-Host 'Lab user password' -AsSecureString
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -TestUserPassword $pw `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -SkipProvisioningWait
```

Runs setup using a pre-supplied `SecureString` instead of an interactive password prompt.

### Example 5: Using the TIBS alias

```powershell
TIBS `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -SkipProvisioningWait
```

Same as Example 1 using the `TIBS` alias.

### Example 6: Allow internal segments to communicate

```powershell
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames user1@company.com,user2@company.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -AllowInternalCommunication `
    -SkipProvisioningWait
```

Same as Example 1 but adds policies that allow `SEG_B_INTERNAL_ALLOWED` and
`SEG_C_INTERNAL_OTHER` to communicate directly with each other. Guest isolation
from Other Internal is preserved.

### Example 7: Enforce one external domain per team

```powershell
New-TeamsInformationBarriersSetup `
    -UserPrincipalName admin@contoso.onmicrosoft.com `
    -GuestNames guest1@fabrikam.com,guest1@litware.com `
    -Password "CreateYourPassword" `
    -AllowedInternalAliases AllowedUser1,AllowedUser2 `
    -OtherInternalAliases InternalUserName1,InternalUserName2 `
    -IsolateGuestDomains `
    -SkipProvisioningWait
```

Creates a dedicated IB segment per unique external guest domain (`SEG_GUEST_FABRIKAM_COM`,
`SEG_GUEST_LITWARE_COM`). Guests from different domains cannot communicate with each other.
Satisfies a strict one-external-domain-per-team requirement.

## PARAMETERS

### -UserPrincipalName

UPN of the admin account (e.g. `admin@contoso.onmicrosoft.com`). Used to authenticate to
Exchange Online and to derive the tenant domain (the portion after the `@` sign).

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowedInternalAliases

Mail aliases (UPN prefix) of existing internal users to place into the *Allowed* group and
segment. These users will be allowed to communicate with guests. Specify aliases of users who
already have an Exchange Online mailbox. If an alias does not exist, a new Entra user is
created but will require an Exchange Online license before EXO provisions a recipient object
and `CustomAttribute1` can be stamped.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OtherInternalAliases

Mail aliases (UPN prefix) of existing internal users to place into the *Other* segment. These
users will be blocked from communicating with guests. Specify aliases of users who already
have an Exchange Online mailbox. If an alias does not exist, a new Entra user is created but
will require an Exchange Online license before EXO provisions a recipient object and
`CustomAttribute1` can be stamped.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -GuestNames

One or more external guest email addresses to invite and include in the guest segment.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TestUserPassword

`SecureString` password for new internal test users. Use `-Password` for a plain-text
alternative. If neither is provided, the command prompts interactively.

```yaml
Type: SecureString
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Password

Plain-text password for new internal users. Converted to `SecureString` internally.
If neither `-Password` nor `-TestUserPassword` is supplied, the command prompts interactively.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IbAllowGroupDisplayName

Display name of the Entra security group created for allowed internal users.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: IB-Allow-Team
Accept pipeline input: False
Accept wildcard characters: False
```

### -AttrGuest

`CustomAttribute1` value stamped on guest recipients. IB segment `SEG_A_GUESTS` filters on
this value.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: Guest
Accept pipeline input: False
Accept wildcard characters: False
```

### -AttrAllowed

`CustomAttribute1` value stamped on allowed internal recipients. IB segment
`SEG_B_INTERNAL_ALLOWED` filters on this value.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: Allowed
Accept pipeline input: False
Accept wildcard characters: False
```

### -AttrOther

`CustomAttribute1` value stamped on other (blocked) internal recipients. IB segment
`SEG_C_INTERNAL_OTHER` filters on this value.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: Other
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogDirectory

Directory where per-run timestamped log files are written. A new file named
`Logging_yyyyMMdd_HHmmss.txt` is created on each run.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: $env:TEMP\TeamsInformationBarriersSetup
Accept pipeline input: False
Accept wildcard characters: False
```

### -ShowBanner

Controls whether the Exchange Online connection banner is displayed. Accepts a Boolean.
Pass `-ShowBanner $false` to suppress the banner.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -StayConnected

Skips `Connect-ExchangeOnline` and uses the existing session. Use this when re-running after
a partial failure or when already authenticated to avoid a second interactive login.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipProvisioningWait

Skips the EXO recipient provisioning poll and proceeds immediately to stamp `CustomAttribute1`.
Use this when all internal users already have Exchange Online mailboxes from a prior run, or to
skip the wait and re-run with `-StayConnected` once provisioning completes.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllowInternalCommunication

When specified, creates an alternative policy set that allows `SEG_B_INTERNAL_ALLOWED` and
`SEG_C_INTERNAL_OTHER` to communicate directly with each other in addition to their default
rights. Guest isolation from `SEG_C` is preserved.

> **Note:** Because SEG_B bridges guests (SEG_A) and SEG_C, data isolation is weakened in
> shared spaces (Teams channels, meetings). Evaluate against your compliance requirements.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -IsolateGuestDomains

When specified, each unique external guest domain receives its own organization segment
(e.g. `SEG_GUEST_FABRIKAM_COM` for `fabrikam.com`) instead of the single flat `SEG_A_GUESTS`
segment. Each domain segment gets an Allow policy scoped to itself and `SEG_B_INTERNAL_ALLOWED`.
Guests from different domains are implicitly blocked from each other, enforcing a strict
one-external-domain-per-team rule without requiring separate Block policies.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:
Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf

Shows what would happen if the command runs without making changes.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm

Prompts for confirmation before each change.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf
Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters

This cmdlet supports the common parameters: `-Debug`, `-ErrorAction`, `-ErrorVariable`,
`-InformationAction`, `-InformationVariable`, `-OutVariable`, `-OutBuffer`,
`-PipelineVariable`, `-Verbose`, `-WarningAction`, and `-WarningVariable`.
For more information, see [about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input.

## OUTPUTS

### System.Management.Automation.PSCustomObject

Returns a summary object with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `TenantDomain` | String | Derived tenant domain (e.g. `contoso.onmicrosoft.com`) |
| `GroupId` | String | Object ID of the IB-Allow-Team security group |
| `AllowedUserCount` | Int | Number of internal users in the Allowed segment |
| `OtherUserCount` | Int | Number of internal users in the Other segment |
| `GuestCount` | Int | Number of guest users processed |
| `Segments` | String[] | Names of the organization segments created |
| `Policies` | String[] | Names of the IB policies created |

## NOTES

**Prerequisites before first run:**

1. **Scoped directory search** must be enabled in the Teams admin center
   (**Teams settings > Search by name**). Wait at least a few hours after enabling.
   See: [information-barriers-policies](https://learn.microsoft.com/en-us/purview/information-barriers-policies)
2. **Teams Open mode**: Teams groups created before IB was enabled are in Open mode and will
   not enforce IB policies until updated to Implicit mode using the
   [Microsoft mode-update script](https://learn.microsoft.com/en-us/purview/information-barriers-teams-powershell-script).
3. **IB mode**: verify your tenant is in SingleSegment or MultiSegment mode
   (`Get-PolicyConfig` in Security & Compliance PowerShell). Legacy mode limits you to 250 segments.
4. **Federation**: IB policies do NOT apply to federated external users. Only B2B guests
   invited via Microsoft Entra are covered.

**Required modules** (installed automatically from PSGallery if missing):

- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Groups`
- `Microsoft.Graph.Identity.SignIns`
- `ExchangeOnlineManagement`

**Required permissions**:

| Service | Required roles / scopes |
| --- | --- |
| Microsoft Graph | `User.ReadWrite.All`, `Group.ReadWrite.All`, `Directory.ReadWrite.All` |
| Exchange Online | Exchange Administrator or equivalent |
| Security & Compliance | Compliance Administrator or IB Administrator |

**IB policy propagation** takes 30–60 minutes after `Start-InformationBarrierPoliciesApplication`
for enforcement to take effect across all Teams conversations. Check status with:
`Get-InformationBarrierPoliciesApplicationStatus`

**Exchange Online licensing**: Internal users must have at minimum an Exchange Online Plan 1
or Kiosk license to appear as `Mailbox` objects in EXO. Without a license, EXO will not
provision a recipient object and `CustomAttribute1` cannot be stamped. Guest users do NOT need
a license — they appear as `MailUser` objects automatically.

**Mailbox provisioning delay**: Newly created Entra users may take several minutes to appear
in Exchange Online as either a `Mailbox` (licensed) or `MailUser` (unlicensed) object.
The command polls up to 3 minutes (6 × 30s) per user. Use `-SkipProvisioningWait` to bypass
the poll when users already have Exchange Online objects.

**Alias**: `TIBS` is exported as a convenience alias for `New-TeamsInformationBarriersSetup`.

## RELATED LINKS

- [about_TeamsInformationBarriersSetup](about_TeamsInformationBarriersSetup)
- [Information barriers in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/information-barriers-in-teams)
- [New-InformationBarrierPolicy](https://learn.microsoft.com/en-us/powershell/module/exchange/new-informationbarrierpolicy)
- [New-OrganizationSegment](https://learn.microsoft.com/en-us/powershell/module/exchange/new-organizationsegment)
- [Start-InformationBarrierPoliciesApplication](https://learn.microsoft.com/en-us/powershell/module/exchange/start-informationbarrierpoliciesapplication)
- [Get-ExoInformationBarrierRelationship](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-exoinformationbarrierrelationship)
- [Get-InformationBarrierRecipientStatus (legacy)](https://learn.microsoft.com/en-us/powershell/module/exchange/get-informationbarrierrecipientstatus)
