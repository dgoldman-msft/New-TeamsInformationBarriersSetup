function Invoke-CmdletProcessGate {
    <#
    .SYNOPSIS
        Invokes ShouldProcess on a provided cmdlet instance.
    .DESCRIPTION
        Uses reflection to call the two-argument ShouldProcess overload on the
        calling PSCmdlet. This keeps helper functions independent while still
        honoring -WhatIf and -Confirm behavior from the public entry point.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance.
    .PARAMETER Target
        The operation target shown to ShouldProcess.
    .PARAMETER Action
        The action text shown to ShouldProcess.
    .OUTPUTS
        System.Boolean
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    $method = $Cmdlet.GetType().GetMethod('ShouldProcess', [Type[]]@([string], [string]))
    if (-not $method) {
        return $false
    }

    return [bool]$method.Invoke($Cmdlet, @($Target, $Action))
}

function Convert-ToODataLiteral {
    <#
    .SYNOPSIS
        Escapes single quotes for OData filter literals.
    .DESCRIPTION
        Converts a raw string value into an OData-safe literal fragment by doubling
        embedded single quotes.
    .PARAMETER Value
        The input string to escape.
    .OUTPUTS
        System.String
    #>
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-OrCreateInternalUser {
    <#
    .SYNOPSIS
        Gets an internal user or creates it when missing.
    .DESCRIPTION
        Looks up a user by UPN in Microsoft Graph and creates the account if it does
        not exist, including password profile setup.
    .PARAMETER Alias
        Alias/mail nickname for the user.
    .PARAMETER Domain
        Tenant domain suffix used to build UPN.
    .PARAMETER SecurePassword
        Password for new account creation.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Alias,
        [string]$Domain,
        [System.Security.SecureString]$SecurePassword,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $upn = "$Alias@$Domain"
    $u = Get-MgUser -UserId $upn -ErrorAction SilentlyContinue
    if ($u) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) User exists: $upn" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $u
    }

    Write-ToLogFile -StringObject "$(Get-TimeStamp) Creating internal user: $upn" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $upn -Action 'Create Microsoft Graph user')) {
        return $null
    }

    $bstr = [System.IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

        $newUser = New-MgUser `
            -DisplayName $Alias `
            -UserPrincipalName $upn `
            -MailNickname $Alias `
            -AccountEnabled:$true `
            -PasswordProfile @{ Password = $plainPassword; ForceChangePasswordNextSignIn = $false } `
            -ErrorAction Stop
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Created user: $upn" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $newUser
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to create user '$upn'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Get-OrCreateInternalUser] Failed to create user '$upn'. Error: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-OrCreateSecurityGroup {
    <#
    .SYNOPSIS
        Gets a security group by display name or creates it.
    .DESCRIPTION
        Returns the first matching Microsoft Graph group; if not found, creates a
        new mail-disabled security group with a unique mail nickname.
    .PARAMETER DisplayName
        The security group display name.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DisplayName,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $existing = Get-MgGroup -Filter "displayName eq '$DisplayName'" -ConsistencyLevel eventual -All -ErrorAction SilentlyContinue
    if ($existing) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Group exists: $DisplayName" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return ($existing | Select-Object -First 1)
    }

    $nick = "iballowteam$(Get-Random -Minimum 10000 -Maximum 99999)"
    Write-ToLogFile -StringObject "$(Get-TimeStamp) Creating security group: $DisplayName (MailNickname: $nick)" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $DisplayName -Action 'Create security group')) {
        return $null
    }

    try {
        $group = New-MgGroup -DisplayName $DisplayName -MailEnabled:$false -MailNickname $nick -SecurityEnabled:$true -ErrorAction Stop
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Created security group: $DisplayName" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $group
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to create security group '$DisplayName'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Get-OrCreateSecurityGroup] Failed to create security group '$DisplayName'. Error: $($_.Exception.Message)"
        return $null
    }
}

function Add-UserToGroupIfMissing {
    <#
    .SYNOPSIS
        Adds a user to a group when membership is missing.
    .DESCRIPTION
        Checks existing group members and adds the user only if needed. Supports
        both New-MgGroupMemberByRef and New-MgGroupMember cmdlet variants.
    .PARAMETER GroupId
        Target Microsoft Graph group id.
    .PARAMETER UserId
        Directory object id of the user to add.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$GroupId,
        [string]$UserId,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $members = Get-MgGroupMember -GroupId $GroupId -All -ErrorAction SilentlyContinue
    if ($members | Where-Object { $_.Id -eq $UserId }) {
        return
    }

    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $GroupId -Action "Add user '$UserId' to security group")) {
        return
    }

    try {
        if (Get-Command -Name New-MgGroupMemberByRef -ErrorAction SilentlyContinue) {
            $refBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" }
            New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter $refBody -ErrorAction Stop | Out-Null
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Added user '$UserId' to group '$GroupId'." -LogFile $script:TIBS_LogFile -ForegroundColor Green
            return
        }

        if (Get-Command -Name New-MgGroupMember -ErrorAction SilentlyContinue) {
            New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId -ErrorAction Stop | Out-Null
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Added user '$UserId' to group '$GroupId'." -LogFile $script:TIBS_LogFile -ForegroundColor Green
            return
        }

        throw 'No supported Microsoft Graph group-member add cmdlet was found (expected New-MgGroupMemberByRef or New-MgGroupMember).'
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to add user '$UserId' to group '$GroupId'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Add-UserToGroupIfMissing] Failed to add user '$UserId' to group '$GroupId'. Error: $($_.Exception.Message)"
    }
}

function Get-OrCreateGuestUser {
    <#
    .SYNOPSIS
        Gets a guest user by email or creates an invitation.
    .DESCRIPTION
        Attempts guest resolution by mail and otherMails, and sends a Graph
        invitation if no guest object is found.
    .PARAMETER Email
        Guest email address.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Email,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $escapedEmail = Convert-ToODataLiteral -Value $Email
    $existing = Get-MgUser -Filter "mail eq '$escapedEmail'" -ConsistencyLevel eventual -All -ErrorAction SilentlyContinue
    if ($existing) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Guest object already exists for: $Email" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return ($existing | Select-Object -First 1)
    }

    $guestMatches = @(Get-MgUser -Filter "userType eq 'Guest'" -ConsistencyLevel eventual -All -Property Id,DisplayName,Mail,OtherMails,UserPrincipalName -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Mail -eq $Email) -or
            ($_.OtherMails -contains $Email)
        })
    if ($guestMatches) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Guest object already exists for: $Email" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return ($guestMatches | Select-Object -First 1)
    }

    Write-ToLogFile -StringObject "$(Get-TimeStamp) Inviting guest (creates guest object): $Email" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $Email -Action 'Invite guest user')) {
        return $null
    }

    try {
        $inv = New-MgInvitation -InvitedUserEmailAddress $Email -InviteRedirectUrl 'https://myapps.microsoft.com' -SendInvitationMessage:$false -ErrorAction Stop
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Guest invitation created for: $Email" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $inv.InvitedUser
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to invite guest '$Email'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Get-OrCreateGuestUser] Failed to invite guest '$Email'. Error: $($_.Exception.Message)"
        return $null
    }
}

function Resolve-GuestRecipientIdentityForSetUser {
    <#
    .SYNOPSIS
        Resolves Exchange recipient identity for a guest email.
    .DESCRIPTION
        Looks up the Exchange recipient using ExternalEmailAddress and falls back to
        searching proxy addresses, returning an identity string for Set-User.
    .PARAMETER GuestEmail
        The guest email address to resolve.
    .OUTPUTS
        System.String
    #>
    param([string]$GuestEmail)

    $smtp = "smtp:$GuestEmail"
    $r = Get-Recipient -ResultSize Unlimited -Filter "ExternalEmailAddress -eq '$smtp'" -ErrorAction SilentlyContinue
    if ($r) {
        return (($r | Select-Object -First 1).Identity)
    }

    $r2 = Get-Recipient -ResultSize Unlimited -ErrorAction SilentlyContinue |
        Where-Object { $_.EmailAddresses -contains $smtp }
    if ($r2) {
        return (($r2 | Select-Object -First 1).Identity)
    }

    return $null
}

function Set-CustomAttribute1-Safe {
    <#
    .SYNOPSIS
        Safely sets CustomAttribute1 on an Exchange recipient.
    .DESCRIPTION
        Applies CustomAttribute1 with error handling and success/error logging.
    .PARAMETER Identity
        Recipient identity accepted by Set-User.
    .PARAMETER Value
        CustomAttribute1 value to assign.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Identity,
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    try {
        if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $Identity -Action "Set CustomAttribute1 to '$Value'")) {
            return
        }

        # CustomAttribute1 lives on Set-Mailbox (licensed users) or Set-MailUser (guests/mail users).
        # Set-User does not expose this parameter.
        try {
            Set-Mailbox -Identity $Identity -CustomAttribute1 $Value -ErrorAction Stop
        }
        catch {
            # Not a mailbox — try as a mail user (guests are MailUser objects in EXO).
            Set-MailUser -Identity $Identity -CustomAttribute1 $Value -ErrorAction Stop
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) SUCCESS: Set CustomAttribute1='$Value' on $Identity" -LogFile $script:TIBS_LogFile -ForegroundColor Green
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to set CustomAttribute1 on $Identity. $_" -LogFile $script:TIBS_LogFile -ForegroundColor Red
    }
}

function Get-OrCreateOrganizationSegment {
    <#
    .SYNOPSIS
        Gets an organization segment by name or creates it.
    .DESCRIPTION
        Checks for an existing organization segment and creates it with the provided
        user filter when missing.
    .PARAMETER Name
        Organization segment name.
    .PARAMETER Filter
        UserGroupFilter expression.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Name,
        [string]$Filter,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $seg = Get-OrganizationSegment -Identity $Name -ErrorAction SilentlyContinue
    if ($seg) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Segment exists: $Name" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $seg
    }

    Write-ToLogFile -StringObject "$(Get-TimeStamp) Creating segment: $Name" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $Name -Action 'Create organization segment')) {
        return $null
    }

    try {
        $newSeg = New-OrganizationSegment -Name $Name -UserGroupFilter $Filter -ErrorAction Stop
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Created segment: $Name" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $newSeg
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to create segment '$Name'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Get-OrCreateOrganizationSegment] Failed to create segment '$Name'. Error: $($_.Exception.Message)"
        return $null
    }
}

function Get-OrCreateInformationBarrierPolicy {
    <#
    .SYNOPSIS
        Gets an information barrier policy or creates it.
    .DESCRIPTION
        Creates either a Blocked or Allowed policy for an assigned segment and target
        segments when the named policy does not yet exist.
    .PARAMETER Name
        Policy name.
    .PARAMETER AssignedSegment
        Segment assigned to the policy.
    .PARAMETER Mode
        Policy mode: Blocked or Allowed.
    .PARAMETER Targets
        Target segments for block/allow behavior.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Name,
        [string]$AssignedSegment,
        [ValidateSet('Blocked', 'Allowed')]
        [string]$Mode,
        [string[]]$Targets,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $pol = Get-InformationBarrierPolicy -Identity $Name -ErrorAction SilentlyContinue
    if ($pol) {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Policy exists: $Name" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $pol
    }

    Write-ToLogFile -StringObject "$(Get-TimeStamp) Creating IB policy: $Name ($Mode)" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
    if (-not (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $Name -Action 'Create information barrier policy')) {
        return $null
    }

    try {
        $newPol = if ($Mode -eq 'Blocked') {
            New-InformationBarrierPolicy -Name $Name -AssignedSegment $AssignedSegment -SegmentsBlocked $Targets -State Inactive -ErrorAction Stop
        }
        else {
            New-InformationBarrierPolicy -Name $Name -AssignedSegment $AssignedSegment -SegmentsAllowed $Targets -State Inactive -ErrorAction Stop
        }
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Created IB policy: $Name ($Mode)" -LogFile $script:TIBS_LogFile -ForegroundColor Green
        return $newPol
    }
    catch {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to create IB policy '$Name'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
        Write-Warning "[Get-OrCreateInformationBarrierPolicy] Failed to create IB policy '$Name'. Error: $($_.Exception.Message)"
        return $null
    }
}

function Set-InformationBarrierPolicyActive {
    <#
    .SYNOPSIS
        Activates an information barrier policy when inactive.
    .DESCRIPTION
        Finds the named policy and sets state to Active when needed.
    .PARAMETER Name
        Policy name to activate.
    .PARAMETER Cmdlet
        The caller's PSCmdlet instance used for ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $p = Get-InformationBarrierPolicy -Identity $Name -ErrorAction SilentlyContinue
    if (-not $p) {
        Write-Warning "Policy '$Name' not found. Skipping activation."
        return
    }

    if ($p.State -ne 'Active') {
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Activating policy: $Name" -LogFile $script:TIBS_LogFile -ForegroundColor Yellow
        if (Invoke-CmdletProcessGate -Cmdlet $Cmdlet -Target $Name -Action 'Activate information barrier policy') {
            try {
                Set-InformationBarrierPolicy -Identity $Name -State Active -ErrorAction Stop | Out-Null
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Policy '$Name' activated successfully." -LogFile $script:TIBS_LogFile -ForegroundColor Green
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to activate policy '$Name'. Error: $($_.Exception.Message)" -LogFile $script:TIBS_LogFile -ForegroundColor Red
                Write-Warning "[Set-InformationBarrierPolicyActive] Failed to activate policy '$Name'. Error: $($_.Exception.Message)"
            }
        }
    }
}