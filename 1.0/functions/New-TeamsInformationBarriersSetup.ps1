function New-TeamsInformationBarriersSetup {
    <#
        .SYNOPSIS
            Builds a repeatable Information Barrier lab configuration for Teams in Microsoft 365.

        .DESCRIPTION
            New-TeamsInformationBarriersSetup automates end-to-end setup of a Microsoft Teams
            Information Barriers (IB) configuration in a Microsoft 365 tenant. The command
            is re-runnable: existing users, groups, segments, and policies are detected and
            reused when present.

            Phase 0 — Identity (Microsoft Graph)
              Creates or reuses internal test users in Allowed and Other groups, creates an
              Entra security group for the allowed users, and invites external guests via the
              Graph invitation API.

            Phase 1 — Exchange Online
              Connects to Exchange Online (unless -StayConnected is specified) and polls until
              each internal user appears as either a Mailbox (licensed) or MailUser (unlicensed)
              object in EXO. Both types support CustomAttribute1 and IB segments. Connects to
              Security and Compliance PowerShell for segment and policy management.

            Phase 2 — Recipient tagging
              Stamps CustomAttribute1 on each mailbox (Set-Mailbox) or mail user (Set-MailUser)
              with the value Allowed, Other, or Guest. IB segments key on this attribute.

            Phase 3 — Segments
              Creates three organization segments:
                SEG_A_GUESTS           — CustomAttribute1 -eq 'Guest'
                SEG_B_INTERNAL_ALLOWED — CustomAttribute1 -eq 'Allowed'
                SEG_C_INTERNAL_OTHER   — CustomAttribute1 -eq 'Other'

            Phase 4 — Policies and enforcement
              Default (four symmetric IB policies):
                Block-Guest-To-Internal-Other    (SEG_A_GUESTS      blocks SEG_C_INTERNAL_OTHER)
                Allow-Guest-To-Team              (SEG_A_GUESTS      allows SEG_A_GUESTS + SEG_B_INTERNAL_ALLOWED)
                Block-InternalOther-To-Guest     (SEG_C_INTERNAL_OTHER   blocks SEG_A_GUESTS)
                Allow-InternalAllowed-To-Guest   (SEG_B_INTERNAL_ALLOWED allows SEG_A_GUESTS + SEG_B_INTERNAL_ALLOWED)

              With -AllowInternalCommunication (five symmetric IB policies — adds B<->C communication):
                Block-Guest-To-Internal-Other    (SEG_A_GUESTS      blocks SEG_C_INTERNAL_OTHER)
                Allow-Guest-To-Team              (SEG_A_GUESTS      allows SEG_A_GUESTS + SEG_B_INTERNAL_ALLOWED)
                Block-InternalOther-To-Guest     (SEG_C_INTERNAL_OTHER   blocks SEG_A_GUESTS)
                Allow-InternalAllowed-To-All     (SEG_B_INTERNAL_ALLOWED allows SEG_A_GUESTS + SEG_B_INTERNAL_ALLOWED + SEG_C_INTERNAL_OTHER)
                Allow-InternalOther-To-Allowed   (SEG_C_INTERNAL_OTHER   allows SEG_B_INTERNAL_ALLOWED + SEG_C_INTERNAL_OTHER)
              Calls Start-InformationBarrierPoliciesApplication to begin enforcement.

            A timestamped log file is always written to -LogDirectory for every run.

        .PARAMETER UserPrincipalName
            UPN of the admin account (e.g. admin@contoso.onmicrosoft.com).
            Used to authenticate to Exchange Online and to derive the tenant domain
            (the portion after the @ sign is used as the tenant domain).

        .PARAMETER TestUserPassword
            SecureString password used for new internal users. Use -Password to supply a plain-text string instead.

        .PARAMETER Password
            Plain-text password used for new internal users. Converted to SecureString internally.
            If neither -Password nor -TestUserPassword is supplied, the command prompts interactively.

        .PARAMETER AllowedInternalAliases
            Mail aliases (UPN prefix) of internal users to place into the allow-team group and
            segment. These users will be allowed to communicate with guests.

            Specify aliases of EXISTING licensed users (e.g. users who already have an Exchange
            Online mailbox). The command will look up each alias and reuse the existing account.
            If the alias does not exist, a new Entra user is created — but that user will need an
            Exchange Online license (minimum Plan 1 or Kiosk) before EXO provisions a recipient
            object and CustomAttribute1 can be stamped.

        .PARAMETER OtherInternalAliases
            Mail aliases (UPN prefix) of internal users to place into the other internal segment.
            These users will be blocked from communicating with guests.

            Specify aliases of EXISTING licensed users (e.g. users who already have an Exchange
            Online mailbox). The command will look up each alias and reuse the existing account.
            If the alias does not exist, a new Entra user is created — but that user will need an
            Exchange Online license (minimum Plan 1 or Kiosk) before EXO provisions a recipient
            object and CustomAttribute1 can be stamped.

        .PARAMETER GuestNames
            Guest email addresses to invite and include in guest segment setup.

        .PARAMETER IbAllowGroupDisplayName
            Display name for the security group that represents allowed internal users.

        .PARAMETER AttrGuest
            CustomAttribute1 value used to tag guest recipients.

        .PARAMETER AttrAllowed
            CustomAttribute1 value used to tag allow-team internal users.

        .PARAMETER AttrOther
            CustomAttribute1 value used to tag other internal users.

        .PARAMETER LogDirectory
            Directory where per-run log files are written.
            Defaults to %TEMP%\TeamsInformationBarriersSetup.

        .PARAMETER ShowBanner
            Controls whether the Exchange Online connection banner is displayed.
            Accepts a Boolean value. Defaults to $true (banner shown).
            Pass -ShowBanner $false to suppress the banner.

        .PARAMETER StayConnected
            When specified, skips Connect-ExchangeOnline and uses the existing
            session. Useful when you are already connected and want to avoid
            re-authenticating on repeated runs.

        .PARAMETER SkipProvisioningWait
            When specified, skips the EXO recipient provisioning poll and proceeds
            immediately to stamp CustomAttribute1. Use this when the internal test
            users already exist from a prior run and their EXO objects are known to
            be present, or when you want to skip the wait and re-run with -StayConnected
            once provisioning completes.

        .PARAMETER AllowInternalCommunication
            When specified, creates an alternative policy set that allows SEG_B_INTERNAL_ALLOWED
            and SEG_C_INTERNAL_OTHER to communicate directly with each other in addition to their
            default communication rights. Guest isolation from SEG_C is preserved — guests still
            cannot communicate with SEG_C directly.

            NOTE: Because SEG_B can communicate with both guests (SEG_A) and SEG_C, and SEG_C can
            communicate with SEG_B, data isolation is weakened in shared spaces such as Teams
            channels and meetings. Evaluate this against your compliance requirements before use.

        .EXAMPLE
            New-TeamsInformationBarriersSetup `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -Password "CreateYourPassword" `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -SkipProvisioningWait

            Lab setup using four pre-licensed internal users: AllowedUser1 and AllowedUser2 in the
            Allowed segment, InternalUserName1 and InternalUserName2 in the Other segment. Two external
            guests are invited. -SkipProvisioningWait is used because all internal users already have
            Exchange Online mailboxes.

        .EXAMPLE
            New-TeamsInformationBarriersSetup `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -Password "CreateYourPassword" `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -StayConnected `
                -SkipProvisioningWait

            Re-run using an existing Exchange Online session. Use this after a partial failure
            or once Exchange Online licenses have been assigned to any newly created users.

        .EXAMPLE
            New-TeamsInformationBarriersSetup `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -Password "CreateYourPassword" `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -WhatIf -Verbose

            Dry run — simulates all actions without making changes.

        .EXAMPLE
            $pw = Read-Host 'Lab user password' -AsSecureString
            New-TeamsInformationBarriersSetup `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -TestUserPassword $pw `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -SkipProvisioningWait

            Runs setup using a pre-supplied SecureString instead of an interactive password prompt.

        .EXAMPLE
            TIBS `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -Password "CreateYourPassword" `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -SkipProvisioningWait

            Same as Example 1 using the TIBS alias.

        .EXAMPLE
            New-TeamsInformationBarriersSetup `
                -UserPrincipalName admin@contoso.onmicrosoft.com `
                -GuestNames user1@company.com,user2@company.com `
                -Password "CreateYourPassword" `
                -AllowedInternalAliases AllowedUser1,AllowedUser2 `
                -OtherInternalAliases InternalUserName1,InternalUserName2 `
                -AllowInternalCommunication `
                -SkipProvisioningWait

            Same as Example 1 but adds an additional policy set that allows the Allowed and Other
            internal segments to communicate with each other. Guest-to-Other isolation is preserved.

        .OUTPUTS
        System.Management.Automation.PSCustomObject

            Returns a summary object with the following properties:

            TenantDomain     [string]   Derived tenant domain (e.g. contoso.onmicrosoft.com)
            GroupId          [string]   Object ID of the IB-Allow-Team security group
            AllowedUserCount [int]      Number of internal users in the Allowed segment
            OtherUserCount   [int]      Number of internal users in the Other segment
            GuestCount       [int]      Number of guest users processed
            Segments         [string[]] Names of the three organization segments created
            Policies         [string[]] Names of the four IB policies created

        .NOTES
            REQUIRED MODULES (installed automatically if missing):
              Microsoft.Graph.Authentication
              Microsoft.Graph.Users
              Microsoft.Graph.Groups
              Microsoft.Graph.Identity.SignIns
              ExchangeOnlineManagement

            REQUIRED PERMISSIONS:
              Microsoft Graph   : User.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All
              Exchange Online   : Exchange Administrator or equivalent
              Security & Compliance : Compliance Administrator or IB Administrator

            IB POLICY PROPAGATION: Allow 30-60 minutes after Start-InformationBarrierPoliciesApplication
            runs for enforcement to take effect across all Teams conversations.

            EXCHANGE ONLINE LICENSING: Internal test users must have at minimum an Exchange Online
            Plan 1 (or Kiosk) license to appear as Mailbox objects in EXO. Without any Exchange
            license, EXO will not provision a recipient object and CustomAttribute1 cannot be stamped.
            Guest users do NOT need a license — they appear as MailUser objects automatically.

            MAILBOX PROVISIONING DELAY: Newly created Entra users can take several minutes to appear
            in Exchange Online as either a Mailbox (licensed) or MailUser (unlicensed) object.
            The command polls up to 3 minutes (6 x 30s) per user. Use -SkipProvisioningWait to
            bypass the poll and continue immediately.
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSAvoidUsingPlainTextForPassword",
        "",
        Scope = "Function",
        Target = "New-TeamsInformationBarriersSetup",
        Justification = "Microsoft Graph New-MgUser PasswordProfile requires a plain text password value."
    )]

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName,

        [Parameter()]
        [System.Security.SecureString]$TestUserPassword,

        [Parameter()]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [ValidateCount(1, 2147483647)]
        [string[]]
        $AllowedInternalAliases,

        [Parameter(Mandatory = $true)]
        [ValidateCount(1, 2147483647)]
        [string[]]
        $OtherInternalAliases,

        [Parameter(Mandatory = $true)]
        [ValidateCount(1, 2147483647)]
        [string[]]
        $GuestNames,

        [Parameter()]
        [string]
        $IbAllowGroupDisplayName = "IB-Allow-Team",

        [Parameter()]
        [string]
        $AttrGuest = "Guest",

        [Parameter()]
        [string]
        $AttrAllowed = "Allowed",

        [Parameter()]
        [string]
        $AttrOther = "Other",

        [Parameter()]
        [string]
        $LogDirectory = (Join-Path $env:TEMP 'TeamsInformationBarriersSetup'),

        [Parameter()]
        [bool]
        $ShowBanner = $true,

        [Parameter()]
        [switch]
        $StayConnected,

        [Parameter()]
        [switch]
        $SkipProvisioningWait,

        [Parameter()]
        [switch]
        $AllowInternalCommunication
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Ensure log directory exists before writing anything.
        if (-not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        # Generate a unique timestamped log file for this run.
        $runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $script:TIBS_LogFile = Join-Path $LogDirectory "Logging_$runStamp.txt"
        $script:TIBS_Sep = "$(Get-TimeStamp) " + ("-" * 80)

        Write-ToLogFile -StringObject $script:TIBS_Sep -LogFile $script:TIBS_LogFile
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Starting New-TeamsInformationBarriersSetup" -LogFile $script:TIBS_LogFile

        #region Module check - install if missing, import only required sub-modules
        # Graph sub-modules needed — avoids importing the full Microsoft.Graph meta-module which is slow.
        $requiredModules = @(
            'Microsoft.Graph.Authentication',  # Connect-MgGraph, Get-MgContext
            'Microsoft.Graph.Users',           # Get-MgUser, New-MgUser
            'Microsoft.Graph.Groups',          # Get-MgGroup, New-MgGroup, Get-MgGroupMember, New-MgGroupMemberByRef
            'Microsoft.Graph.Identity.SignIns', # New-MgInvitation
            'ExchangeOnlineManagement'
        )

        foreach ($moduleName in $requiredModules) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Checking for $moduleName module" -LogFile $script:TIBS_LogFile

            $installed = Get-Module -ListAvailable -Name $moduleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

            if (-not $installed) {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) $moduleName not found. Installing latest version from PSGallery..." `
                    -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
                try {
                    Install-Module -Name $moduleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) $moduleName installed successfully." -LogFile $script:TIBS_LogFile
                }
                catch {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: $moduleName installation failed. Error: $($_.Exception.Message)" `
                        -LogFile $script:TIBS_LogFile -ForegroundColor Red
                    throw
                }
            }
            else {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) $moduleName found v$($installed.Version)." -LogFile $script:TIBS_LogFile
            }

            if (-not (Get-Module -Name $moduleName)) {
                try {
                    Import-Module -Name $moduleName -ErrorAction Stop
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) $moduleName imported into the current session." -LogFile $script:TIBS_LogFile
                }
                catch {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: $moduleName import failed. Error: $($_.Exception.Message)" `
                        -LogFile $script:TIBS_LogFile -ForegroundColor Red
                    throw
                }
            }
            else {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) $moduleName already loaded in this session." -LogFile $script:TIBS_LogFile
            }
        }
        #endregion

        $TenantDomain = $UserPrincipalName.Split('@')[1]
        $GuestEmails = $GuestNames

        if ($PSBoundParameters.ContainsKey('Password')) {
            $TestUserPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        }
        elseif (-not $PSBoundParameters.ContainsKey('TestUserPassword')) {
            $TestUserPassword = Read-Host 'Enter lab password for new internal users' -AsSecureString
        }
    }

    process {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 0 - Connect to Microsoft Graph" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        try {
            Connect-MgGraph -Scopes @('User.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All') -ErrorAction Stop | Out-Null
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Connected to Microsoft Graph." -LogFile $script:TIBS_LogFile
        }
        catch {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Microsoft Graph connection failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
            return
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 0 - Create/Get IB Allow group" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        $ibGroup = Get-OrCreateSecurityGroup -DisplayName $IbAllowGroupDisplayName -Cmdlet $PSCmdlet
        if (-not $ibGroup) {
            Write-Warning "No security group object available. If running with -WhatIf, this is expected."
            return
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) IB Allow Group Id: $($ibGroup.Id)" -LogFile $script:TIBS_LogFile -ForegroundColor Green

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 0 - Create/Get internal users" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        $allowedUsers = foreach ($a in $AllowedInternalAliases) {
            Get-OrCreateInternalUser -Alias $a -Domain $TenantDomain -SecurePassword $TestUserPassword -Cmdlet $PSCmdlet
        }
        $otherUsers = foreach ($a in $OtherInternalAliases) {
            Get-OrCreateInternalUser -Alias $a -Domain $TenantDomain -SecurePassword $TestUserPassword -Cmdlet $PSCmdlet
        }
        $allowedUsers = @($allowedUsers | Where-Object { $_ })
        $otherUsers = @($otherUsers | Where-Object { $_ })
        if ($allowedUsers.Count -gt 0 -or $otherUsers.Count -gt 0) {
            Write-Host ''
            Write-Host '  LICENSING NOTICE' -ForegroundColor Yellow
            Write-Host '  -----------------------------------------------------------------------' -ForegroundColor Yellow
            Write-Host '  Internal test users have been created in Entra ID but have NO Exchange' -ForegroundColor Yellow
            Write-Host '  Online license assigned. Without a license (minimum: Exchange Online' -ForegroundColor Yellow
            Write-Host '  Plan 1 or Kiosk), EXO will not provision a recipient object and' -ForegroundColor Yellow
            Write-Host '  CustomAttribute1 cannot be stamped, which will cause IB segment' -ForegroundColor Yellow
            Write-Host '  filters to fail.' -ForegroundColor Yellow
            Write-Host '' -ForegroundColor Yellow
            Write-Host '  ACTION REQUIRED (if not already done):' -ForegroundColor Yellow
            Write-Host '    1. Open the Microsoft 365 admin center (admin.microsoft.com)' -ForegroundColor Yellow
            Write-Host '    2. Go to Users > Active users and assign an Exchange Online license' -ForegroundColor Yellow
            Write-Host '       to each of the following accounts:' -ForegroundColor Yellow
            foreach ($u in ($allowedUsers + $otherUsers)) {
                Write-Host "       - $($u.UserPrincipalName)" -ForegroundColor Yellow
            }
            Write-Host '' -ForegroundColor Yellow
            Write-Host '  Guest users do NOT need a license.' -ForegroundColor Green
            Write-Host '  -----------------------------------------------------------------------' -ForegroundColor Yellow
            Write-Host ''
            Write-ToLogFile -StringObject "$(Get-TimeStamp) LICENSING NOTICE: Internal users require an Exchange Online license before EXO recipient objects are provisioned." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 0 - Add allowed users to IB-Allow-Team group" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        foreach ($u in $allowedUsers) {
            Add-UserToGroupIfMissing -GroupId $ibGroup.Id -UserId $u.Id -Cmdlet $PSCmdlet
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Allowed users added to group. (Other users intentionally NOT added.)" -LogFile $script:TIBS_LogFile -ForegroundColor Green

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 0 - Invite guests (create guest objects)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        foreach ($g in $GuestEmails) {
            Get-OrCreateGuestUser -Email $g -Cmdlet $PSCmdlet | Out-Null
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 1 - Connect to Exchange Online" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        if ($StayConnected) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) -StayConnected specified; skipping Connect-ExchangeOnline and using existing session." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        }
        else {
            try {
                Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ShowBanner:$ShowBanner -ErrorAction Stop
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Connected to Exchange Online." -LogFile $script:TIBS_LogFile
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Exchange Online connection failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
                return
            }
        }

        # Wait for EXO to provision a recipient object for newly created internal users.
        # Licensed users become Mailboxes; unlicensed users become MailUsers.
        # Users with NO Exchange Online license will never appear — use -SkipProvisioningWait
        # in that case and re-run after assigning licenses.
        $internalUPNs = @($allowedUsers + $otherUsers | Where-Object { $_ } | ForEach-Object { $_.UserPrincipalName })
        if ($internalUPNs.Count -gt 0 -and -not $SkipProvisioningWait) {
            Write-Host ''
            Write-Host '  WAITING FOR EXO PROVISIONING' -ForegroundColor Cyan
            Write-Host '  If this poll keeps timing out, the internal users are likely missing' -ForegroundColor Cyan
            Write-Host '  an Exchange Online license. Assign licenses, then re-run with:' -ForegroundColor Cyan
            Write-Host '  -StayConnected -SkipProvisioningWait' -ForegroundColor Cyan
            Write-Host ''
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 2 - Waiting for EXO to provision recipient objects for internal users..." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
            Write-ToLogFile -StringObject "$(Get-TimeStamp) NOTE: Users without an Exchange Online license will never appear as EXO recipients. If this poll times out, assign Exchange Online licenses and re-run with -StayConnected -SkipProvisioningWait." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
            $maxRetries = 6
            $retryDelaySec = 30
            foreach ($upn in $internalUPNs) {
                $attempt = 0
                $provisioned = $false
                while (-not $provisioned -and $attempt -lt $maxRetries) {
                    if ((Get-Mailbox -Identity $upn -ErrorAction SilentlyContinue) -or
                        (Get-MailUser -Identity $upn -ErrorAction SilentlyContinue)) {
                        Write-ToLogFile -StringObject "$(Get-TimeStamp) EXO recipient object ready for $upn." -LogFile $script:TIBS_LogFile
                        $provisioned = $true
                    }
                    else {
                        $attempt++
                        Write-ToLogFile -StringObject "$(Get-TimeStamp) Recipient not yet visible for $upn (attempt $attempt/$maxRetries). Waiting ${retryDelaySec}s..." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
                        Start-Sleep -Seconds $retryDelaySec
                    }
                }
                if (-not $provisioned) {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) WARNING: EXO recipient for $upn not visible after $($maxRetries * $retryDelaySec)s. Likely missing Exchange Online license. Assign a license then re-run with -StayConnected -SkipProvisioningWait." -LogFile $script:TIBS_LogFile -ForegroundColor Red
                    Write-Warning "[EXO] Recipient for $upn not provisioned. Assign an Exchange Online license and re-run with -StayConnected -SkipProvisioningWait."
                }
            }
        }
        elseif ($SkipProvisioningWait) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 2 - Skipping EXO provisioning wait (-SkipProvisioningWait specified)." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 2 - Stamp CustomAttribute1 in Exchange (required for IB segment filters)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        foreach ($u in $allowedUsers) {
            Set-CustomAttribute1-Safe -Identity $u.UserPrincipalName -Value $AttrAllowed -Cmdlet $PSCmdlet
        }
        foreach ($u in $otherUsers) {
            Set-CustomAttribute1-Safe -Identity $u.UserPrincipalName -Value $AttrOther -Cmdlet $PSCmdlet
        }

        foreach ($g in $GuestEmails) {
            $guestIdentity = Resolve-GuestRecipientIdentityForSetUser -GuestEmail $g
            if (-not $guestIdentity) {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Could not resolve EXO recipient for guest '$g'. Ensure guest exists as a recipient in EXO, then re-run." -LogFile $script:TIBS_LogFile -ForegroundColor Red
                continue
            }
            Set-CustomAttribute1-Safe -Identity $guestIdentity -Value $AttrGuest -Cmdlet $PSCmdlet
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 2 - Validate attributes (Exchange)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        $attrValues = @($AttrGuest, $AttrAllowed, $AttrOther)
        @(
            Get-Mailbox  -ResultSize Unlimited | Select-Object Name, UserPrincipalName, CustomAttribute1
            Get-MailUser -ResultSize Unlimited | Select-Object Name, UserPrincipalName, CustomAttribute1
        ) | Where-Object { $_.CustomAttribute1 -in $attrValues } |
        Sort-Object CustomAttribute1 |
        Format-Table -AutoSize

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 1 (continued) - Connect to Security & Compliance PowerShell (IPPSSession)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        try {
            Connect-IPPSSession -ErrorAction Stop | Out-Null
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Connected to Security & Compliance PowerShell." -LogFile $script:TIBS_LogFile
        }
        catch {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Security & Compliance PowerShell connection failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
            throw
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 2 - Create IB segments (based on CustomAttribute1)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        Get-OrCreateOrganizationSegment -Name "SEG_A_GUESTS"           -Filter "CustomAttribute1 -eq '$AttrGuest'"   -Cmdlet $PSCmdlet | Out-Null
        Get-OrCreateOrganizationSegment -Name "SEG_B_INTERNAL_ALLOWED" -Filter "CustomAttribute1 -eq '$AttrAllowed'" -Cmdlet $PSCmdlet | Out-Null
        Get-OrCreateOrganizationSegment -Name "SEG_C_INTERNAL_OTHER"   -Filter "CustomAttribute1 -eq '$AttrOther'"   -Cmdlet $PSCmdlet | Out-Null

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Segments ready:" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        Get-OrganizationSegment | Format-List Name, UserGroupFilter

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 3 - Create IB policies (inactive first)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        # Policies must be symmetric: every segment referenced as a target must also have its own assigned policy.
        # SEG_A_GUESTS policies (what guests can/cannot communicate with) — same for both modes
        Get-OrCreateInformationBarrierPolicy -Name "Block-Guest-To-Internal-Other"       -AssignedSegment "SEG_A_GUESTS"           -Mode "Blocked" -Targets @("SEG_C_INTERNAL_OTHER")                                                       -Cmdlet $PSCmdlet | Out-Null
        Get-OrCreateInformationBarrierPolicy -Name "Allow-Guest-To-Team"                 -AssignedSegment "SEG_A_GUESTS"           -Mode "Allowed" -Targets @("SEG_A_GUESTS", "SEG_B_INTERNAL_ALLOWED")                               -Cmdlet $PSCmdlet | Out-Null
        # SEG_C_INTERNAL_OTHER: block guests — same for both modes
        Get-OrCreateInformationBarrierPolicy -Name "Block-InternalOther-To-Guest"        -AssignedSegment "SEG_C_INTERNAL_OTHER"   -Mode "Blocked" -Targets @("SEG_A_GUESTS")                                                            -Cmdlet $PSCmdlet | Out-Null
        if ($AllowInternalCommunication) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) -AllowInternalCommunication specified: creating extended policy set (B<->C communication allowed)." -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
            # SEG_B: allowed team communicates with guests, each other, AND other internal segment
            Get-OrCreateInformationBarrierPolicy -Name "Allow-InternalAllowed-To-All"     -AssignedSegment "SEG_B_INTERNAL_ALLOWED" -Mode "Allowed" -Targets @("SEG_A_GUESTS", "SEG_B_INTERNAL_ALLOWED", "SEG_C_INTERNAL_OTHER") -Cmdlet $PSCmdlet | Out-Null
            # SEG_C: other internal segment communicates with allowed team and each other (symmetric)
            Get-OrCreateInformationBarrierPolicy -Name "Allow-InternalOther-To-Allowed"   -AssignedSegment "SEG_C_INTERNAL_OTHER"   -Mode "Allowed" -Targets @("SEG_B_INTERNAL_ALLOWED", "SEG_C_INTERNAL_OTHER")                    -Cmdlet $PSCmdlet | Out-Null
        }
        else {
            # SEG_B: allowed team communicates with guests and each other only (default isolation)
            Get-OrCreateInformationBarrierPolicy -Name "Allow-InternalAllowed-To-Guest"   -AssignedSegment "SEG_B_INTERNAL_ALLOWED" -Mode "Allowed" -Targets @("SEG_A_GUESTS", "SEG_B_INTERNAL_ALLOWED")                              -Cmdlet $PSCmdlet | Out-Null
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Policies created:" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        Get-InformationBarrierPolicy | Format-Table Name, State, AssignedSegment, Segments* -Auto

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 4 - Activate policies" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        Set-InformationBarrierPolicyActive -Name "Block-Guest-To-Internal-Other"    -Cmdlet $PSCmdlet
        Set-InformationBarrierPolicyActive -Name "Allow-Guest-To-Team"              -Cmdlet $PSCmdlet
        Set-InformationBarrierPolicyActive -Name "Block-InternalOther-To-Guest"     -Cmdlet $PSCmdlet
        if ($AllowInternalCommunication) {
            Set-InformationBarrierPolicyActive -Name "Allow-InternalAllowed-To-All"    -Cmdlet $PSCmdlet
            Set-InformationBarrierPolicyActive -Name "Allow-InternalOther-To-Allowed"  -Cmdlet $PSCmdlet
        }
        else {
            Set-InformationBarrierPolicyActive -Name "Allow-InternalAllowed-To-Guest"  -Cmdlet $PSCmdlet
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Policies active:" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        Get-InformationBarrierPolicy | Format-Table Name, State, AssignedSegment, Segments* -Auto

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 4 - Apply policies (enforcement begins after this)" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        if ($PSCmdlet.ShouldProcess("Information barrier policies", "Apply organization-wide")) {
            try {
                Start-InformationBarrierPoliciesApplication -Confirm:$false -ErrorAction Stop | Out-Null
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Policy application invoked." -LogFile $script:TIBS_LogFile -ForegroundColor Green
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to start policy application. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
                Write-Warning "[InformationBarrier] Failed to start policy application. Error: $($_.Exception.Message)"
            }
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Phase 4 - Validate IB relationships" -LogFile $script:TIBS_LogFile -ForegroundColor Cyan
        $validateAllowedUpn = "$($AllowedInternalAliases[0])@$TenantDomain"
        $validateOtherUpn = "$($OtherInternalAliases[0])@$TenantDomain"

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Validate Guest vs Allowed Internal:" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        try {
            Get-InformationBarrierRecipientStatus -Identity $GuestEmails[0] -Identity2 $validateAllowedUpn -ErrorAction Stop
        }
        catch {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Recipient status check failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
            Write-Warning "[InformationBarrier] Recipient status check failed. Error: $($_.Exception.Message)"
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Validate Guest vs Other Internal:" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        try {
            Get-InformationBarrierRecipientStatus -Identity $GuestEmails[0] -Identity2 $validateOtherUpn -ErrorAction Stop
        }
        catch {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Recipient status check failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
            Write-Warning "[InformationBarrier] Recipient status check failed. Error: $($_.Exception.Message)"
        }

        # Return key artifacts so callers can inspect results programmatically.
        [pscustomobject]@{
            TenantDomain     = $TenantDomain
            GroupId          = $ibGroup.Id
            AllowedUserCount = @($allowedUsers).Count
            OtherUserCount   = @($otherUsers).Count
            GuestCount       = @($GuestEmails).Count
            Segments         = @("SEG_A_GUESTS", "SEG_B_INTERNAL_ALLOWED", "SEG_C_INTERNAL_OTHER")
            Policies         = if ($AllowInternalCommunication) {
                                   @("Block-Guest-To-Internal-Other", "Allow-Guest-To-Team", "Block-InternalOther-To-Guest", "Allow-InternalAllowed-To-All", "Allow-InternalOther-To-Allowed")
                               } else {
                                   @("Block-Guest-To-Internal-Other", "Allow-Guest-To-Team", "Block-InternalOther-To-Guest", "Allow-InternalAllowed-To-Guest")
                               }
        }
    }

    end {
        #region Disconnect from Exchange Online unless -StayConnected was passed
        if (-not $StayConnected) {
            try {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Disconnected from Exchange Online successfully." -LogFile $script:TIBS_LogFile
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) WARNING: Disconnect from Exchange Online failed. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
                Write-Warning "[ExchangeOnline] Disconnect failed. Error: $_"
            }
        }
        else {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Session left open (-StayConnected specified)." -LogFile $script:TIBS_LogFile
        }
        #endregion

        Write-ToLogFile -StringObject "$(Get-TimeStamp) New-TeamsInformationBarriersSetup completed." -LogFile $script:TIBS_LogFile
        Write-ToLogFile -StringObject $script:TIBS_Sep -LogFile $script:TIBS_LogFile
        Write-Host "Log file written to: $($script:TIBS_LogFile)" -ForegroundColor Cyan
    }
}