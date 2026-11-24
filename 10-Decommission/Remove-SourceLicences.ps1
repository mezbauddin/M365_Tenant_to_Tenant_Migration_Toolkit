<#
.SYNOPSIS
    Removes licences from users in the SOURCE tenant once the migration is finished, skips anyone who still needs
    one, and lists every subscription with the exact billing step that stops it renewing.

.DESCRIPTION
    TL;DR: Run it at T+30 of the 10 checklist, after the final incrementals, exports and hold decisions. Run with
    -WhatIf first. It pick-lists the licences in use (or takes -SkuPartNumber / -AllSkus), then for each licensed user:

      Skipped   your own account and -Exclude (break-glass), anyone who can still sign in (block them first with
                07 Block-SourceSignIn.ps1, or pass -IncludeEnabled), and any mailbox on litigation, In-Place or
                retention hold (pass -IncludeHeld only once the hold owner has agreed in writing)
      Removed   licences assigned directly to the user
      Group     licences that come from a group can't be removed from one person. With -IncludeGroupLicences the
                licence is removed from the group itself, but only when no skipped user gets it from that group

    Then it reads every subscription (Graph directory/subscriptions) and writes the billing step for each: cancel if
    it started in the last 7 days, otherwise turn off recurring billing so it ends on its date, or ask the partner if
    it was bought through one. Microsoft has no Graph API to cancel or stop a Microsoft 365 subscription bought
    directly: that last step is in the admin centre (Billing, Your products) or with the partner (CSP).

    Writes LicenceRemoval-<date>.csv (one row per user and licence: Action, Detail) and
    SubscriptionBilling-<date>.csv (one row per subscription: seats, used, end date, NextStep).

    Trap: an unlicensed OneDrive turns read-only at day 60 and is archived at day 93 (default settings). Make the
    OneDrive decision (10 checklist) before you run this for real.
    Trap: removing a licence doesn't delete the user, mailbox or OneDrive. Deleting users does, after retention.
    This script never deletes anyone.
    Tip: free seats still cost money until the subscription ends. Removing licences shows how many seats are spare;
    turning off recurring billing is what stops the charge.

.PARAMETER TenantId
    Source tenant ID (GUID). The script stops if Graph or Exchange Online is signed in anywhere else.

.PARAMETER AdminUpn
    Optional source admin sign-in name, e.g. admin@fabrikam.onmicrosoft.com. Sessions for another account or tenant
    are disconnected first. Your own account is always skipped.

.PARAMETER Exclude
    UPNs that keep their licences, such as a break-glass Global Administrator or a mailbox still being exported.

.PARAMETER Users
    Only these UPNs (comma-separated or an array). Default: every licensed user.

.PARAMETER SkuPartNumber
    Only these licences, e.g. SPB, O365_BUSINESS_PREMIUM, EXCHANGESTANDARD. Default: pick from a numbered list.

.PARAMETER AllSkus
    Every licence in use, without the pick-list (for unattended runs).

.PARAMETER IncludeEnabled
    Also remove licences from accounts that can still sign in. Default: skipped, because they may still be in use.

.PARAMETER IncludeHeld
    Also remove licences from mailboxes on hold. Only after the hold owner's written decision.

.PARAMETER IncludeGroupLicences
    Remove group-assigned licences from the group, when every member who has it from that group is in scope.
    Ignored with -Users, because members outside the list can't be checked.

.PARAMETER SkipHoldCheck
    Don't connect to Exchange Online. Holds are then unknown and nobody is skipped for a hold: use only when the
    readiness check already showed no holds.

.EXAMPLE
    .\Remove-SourceLicences.ps1 -TenantId <source-guid> -AdminUpn admin@fabrikam.onmicrosoft.com -WhatIf

    Dry run: pick the licences, see who would lose what and what to do about each subscription. Changes nothing.

.EXAMPLE
    .\Remove-SourceLicences.ps1 -TenantId <source-guid> -AdminUpn admin@fabrikam.onmicrosoft.com `
        -Exclude breakglass@fabrikam.onmicrosoft.com -AllSkus -Confirm:$false

.NOTES
    Author  : Mezba Uddin (Microsoft MVP)
    Version : 1.0.0
    Date    : 2026-11-24
    Licence : MIT
    Repo    : https://github.com/mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit
    Requires: Microsoft.Graph.Authentication; ExchangeOnlineManagement 3.x for the hold check. Windows PowerShell 5.1
              or PowerShell 7. License Administrator (or User Administrator) for users, Groups Administrator for
              -IncludeGroupLicences, Global Reader or Exchange Administrator for the hold check. Turning off
              recurring billing needs Billing Administrator or Global Administrator, in the admin centre.
    Changes licence assignments in the source only. Never deletes users, mailboxes, OneDrives or subscriptions.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [string]$AdminUpn,
    [string[]]$Exclude = @(),
    [string[]]$Users = @(),
    [string[]]$SkuPartNumber = @(),
    [switch]$AllSkus,
    [switch]$IncludeEnabled,
    [switch]$IncludeHeld,
    [switch]$IncludeGroupLicences,
    [switch]$SkipHoldCheck
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) { throw 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser first.' }
if (-not $SkipHoldCheck -and -not (Get-Module -ListAvailable ExchangeOnlineManagement)) { throw 'Install-Module ExchangeOnlineManagement -Scope CurrentUser first, or use -SkipHoldCheck.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$split = { param($list) @($list | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$Exclude = & $split $Exclude; $Users = & $split $Users; $SkuPartNumber = & $split $SkuPartNumber

function Get-GraphAll([string]$Uri) {
    $out = [System.Collections.Generic.List[object]]::new()
    while ($Uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        foreach ($v in @($page.value)) { $out.Add($v) }
        $Uri = $page.'@odata.nextLink'
    }
    $out
}
function Get-First([string[]]$Items, [int]$Count = 8) {
    $list = @($Items | Where-Object { $_ })
    $text = ($list | Select-Object -First $Count) -join ', '
    if ($list.Count -gt $Count) { $text += " and $($list.Count - $Count) more" }
    $text
}

# ------------------------------------------------------------ Graph: sign in to the right tenant as the right account
$scopes = @('User.ReadWrite.All', 'Directory.Read.All', 'Organization.Read.All', 'LicenseAssignment.ReadWrite.All')
if ($IncludeGroupLicences) { $scopes += 'Group.ReadWrite.All' }
$ctx = Get-MgContext
if ($ctx -and ($ctx.TenantId -ne $TenantId -or ($AdminUpn -and $ctx.Account -ne $AdminUpn) -or @($scopes | Where-Object { $ctx.Scopes -notcontains $_ }))) {
    Write-Host "Graph is signed in as $($ctx.Account) to $($ctx.TenantId) (or without write scopes). Disconnecting." -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null
}
Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome
$ctx = Get-MgContext
if ($ctx.TenantId -ne $TenantId) { throw "Graph signed in to $($ctx.TenantId), not $TenantId. Stopping." }
if ($AdminUpn -and $ctx.Account -ne $AdminUpn) { throw "Graph signed in as $($ctx.Account), not $AdminUpn. Run Disconnect-MgGraph and pick $AdminUpn." }
$org = (Invoke-MgGraphRequest GET 'v1.0/organization?$select=displayName').value | Select-Object -First 1
Write-Host "Signed in as $($ctx.Account) to $($org.displayName) ($($ctx.TenantId))" -ForegroundColor Cyan
$skip = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@($Exclude) + $AdminUpn + $ctx.Account | Where-Object { $_ } | ForEach-Object { [void]$skip.Add($_) }

# ------------------------------------------------------------ licences in use, and which to remove
$skus = @{}
foreach ($s in @(Get-GraphAll 'v1.0/subscribedSkus')) { $skus["$($s.skuId)"] = $s }
$all = @(Get-GraphAll 'v1.0/users?$select=id,displayName,userPrincipalName,accountEnabled,assignedLicenses,licenseAssignmentStates&$top=999')
$licensed = @($all | Where-Object { @($_.assignedLicenses).Count })
if ($Users) {
    $want = [System.Collections.Generic.HashSet[string]]::new([string[]]$Users, [StringComparer]::OrdinalIgnoreCase)
    $missing = @($Users | Where-Object { -not ($all.userPrincipalName -contains $_) })
    if ($missing) { Write-Warning "Not found in the source: $($missing -join ', ')" }
    $licensed = @($licensed | Where-Object { $want.Contains($_.userPrincipalName) })
}
if (-not $licensed) { Write-Host 'Nobody in scope holds a licence. Nothing to remove.' -ForegroundColor Green }

$inUse = @($licensed | ForEach-Object { foreach ($l in @($_.assignedLicenses)) { "$($l.skuId)" } } | Group-Object | ForEach-Object {
        [pscustomobject]@{ SkuId = $_.Name; Name = $(if ($skus[$_.Name]) { $skus[$_.Name].skuPartNumber } else { $_.Name }); Users = $_.Count }
    } | Sort-Object Name)

$chosen = @()
if ($AllSkus) { $chosen = $inUse }
elseif ($SkuPartNumber) {
    $chosen = @($inUse | Where-Object { $SkuPartNumber -contains $_.Name })
    $unknown = @($SkuPartNumber | Where-Object { -not ($inUse.Name -contains $_) })
    if ($unknown) { Write-Warning "Not assigned to anyone in scope: $($unknown -join ', '). In use: $($inUse.Name -join ', ')" }
}
elseif ($inUse) {
    Write-Host ''
    Write-Host 'Licences in use. Pick which to remove:' -ForegroundColor Cyan
    Write-Host '   0  All of them'
    for ($i = 0; $i -lt $inUse.Count; $i++) { Write-Host ("  {0,2}  {1} ({2} user(s))" -f ($i + 1), $inUse[$i].Name, $inUse[$i].Users) }
    do {
        $pick = Read-Host 'Numbers, separated by commas (0 = all, Enter = cancel)'
        if (-not "$pick".Trim()) { Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; return }
        $nums = @("$pick".Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        $ok = $nums.Count -and -not @($nums | Where-Object { $_ -gt $inUse.Count }).Count
        if (-not $ok) { Write-Host "Type numbers from 0 to $($inUse.Count)." -ForegroundColor Yellow }
    } until ($ok)
    $chosen = if ($nums -contains 0) { $inUse } else { @($nums | Sort-Object -Unique | ForEach-Object { $inUse[$_ - 1] }) }
}
$chosenIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($chosen.SkuId), [StringComparer]::OrdinalIgnoreCase)
if ($chosen) { Write-Host "Removing: $($chosen.Name -join ', ')" -ForegroundColor Cyan }

# ------------------------------------------------------------ holds (Exchange Online)
$heldSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$orgHold = $false
if ($chosen -and -not $SkipHoldCheck) {
    $c = Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object State -eq 'Connected' | Select-Object -First 1
    if ($c -and ("$($c.TenantID)" -ne $TenantId -or ($AdminUpn -and "$($c.UserPrincipalName)" -ne $AdminUpn))) {
        Write-Host "Exchange Online is signed in as $($c.UserPrincipalName) to $($c.TenantID). Disconnecting." -ForegroundColor Yellow
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        $c = $null
    }
    if (-not $c) {
        $p = @{ ShowBanner = $false }
        if ($AdminUpn) { $p.UserPrincipalName = $AdminUpn }
        Connect-ExchangeOnline @p
        $c = Get-ConnectionInformation | Where-Object State -eq 'Connected' | Select-Object -First 1
    }
    if ("$($c.TenantID)" -ne $TenantId) { throw "Exchange Online is signed in to tenant $($c.TenantID), not $TenantId. Stopping." }
    Write-Host 'Checking mailbox holds' -ForegroundColor Cyan
    foreach ($m in @(Get-EXOMailbox -ResultSize Unlimited -Properties LitigationHoldEnabled, InPlaceHolds)) {
        if ($m.LitigationHoldEnabled -or @($m.InPlaceHolds | Where-Object { $_ }).Count) { [void]$heldSet.Add("$($m.ExternalDirectoryObjectId)") }
    }
    $orgHold = [bool]@((Get-OrganizationConfig).InPlaceHolds | Where-Object { $_ }).Count
    if ($heldSet.Count) { Write-Host "  $($heldSet.Count) mailbox(es) on hold$(if (-not $IncludeHeld) { ': skipped' })" -ForegroundColor Yellow }
    if ($orgHold) { Write-Warning 'An organisation-wide retention or hold policy applies to every mailbox. Check Purview with the policy owner before you go ahead.' }
}

# ------------------------------------------------------------ decide, user by user
$rows = [System.Collections.Generic.List[object]]::new()
$groupUse = @{}   # groupId -> list of @{ User; SkuId; InScope }
foreach ($u in $licensed) {
    $reason = if ($skip.Contains($u.userPrincipalName)) { 'Skipped: excluded or your own account' }
    elseif ($u.accountEnabled -and -not $IncludeEnabled) { 'Skipped: can still sign in. Block first (07 Block-SourceSignIn.ps1) or use -IncludeEnabled' }
    elseif ($heldSet.Contains("$($u.id)") -and -not $IncludeHeld) { 'Skipped: mailbox on hold. Hold owner decides; then -IncludeHeld' }
    else { '' }
    $direct = @()
    foreach ($l in @($u.assignedLicenses)) {
        $id = "$($l.skuId)"
        $name = if ($skus[$id]) { $skus[$id].skuPartNumber } else { $id }
        $states = @($u.licenseAssignmentStates | Where-Object { "$($_.skuId)" -eq $id })
        $byGroup = @($states | Where-Object { $_.assignedByGroup } | ForEach-Object { "$($_.assignedByGroup)" })
        $isDirect = [bool]@($states | Where-Object { -not $_.assignedByGroup }).Count -or -not $states
        foreach ($g in $byGroup) {
            if (-not $groupUse[$g]) { $groupUse[$g] = [System.Collections.Generic.List[object]]::new() }
            $groupUse[$g].Add([pscustomobject]@{ User = $u.userPrincipalName; SkuId = $id; InScope = (-not $reason -and $chosenIds.Contains($id)) })
        }
        if (-not $chosenIds.Contains($id)) { continue }
        $row = [pscustomobject]@{
            UserPrincipalName = $u.userPrincipalName; DisplayName = $u.displayName; Enabled = $u.accountEnabled
            OnHold = $heldSet.Contains("$($u.id)"); Licence = $name
            AssignedBy = $(if ($isDirect -and $byGroup) { 'Direct and group' } elseif ($isDirect) { 'Direct' } else { 'Group' })
            Action = ''; Detail = ''
        }
        if ($reason) { $row.Action = 'Skipped'; $row.Detail = $reason }
        elseif ($isDirect) { $direct += $id; $row.Action = 'Remove' }
        else { $row.Action = 'Group'; $row.Detail = 'From a group: see the group rows' }
        $rows.Add($row)
    }
    if ($direct) {
        $target = "$($u.userPrincipalName): remove $((@($direct) | ForEach-Object { $skus[$_].skuPartNumber }) -join ', ')"
        $mine = @($rows | Where-Object { $_.UserPrincipalName -eq $u.userPrincipalName -and $_.Action -eq 'Remove' })
        if ($PSCmdlet.ShouldProcess($target, 'Remove licences')) {
            try {
                $body = @{ addLicenses = @(); removeLicenses = [string[]]@($direct) } | ConvertTo-Json -Depth 4
                Invoke-MgGraphRequest -Method POST -Uri "v1.0/users/$($u.id)/assignLicense" -Body $body -ContentType 'application/json' | Out-Null
                $mine | ForEach-Object { $_.Action = 'Removed'; if ($_.AssignedBy -eq 'Direct and group') { $_.Detail = 'Direct removed; still has it from a group' } }
                Write-Host "  Removed  $target" -ForegroundColor Green
            }
            catch {
                $err = $_.Exception.Message
                $mine | ForEach-Object { $_.Action = 'Failed'; $_.Detail = $err }
                Write-Host "  FAILED   $target : $err" -ForegroundColor Red
            }
        }
        else { $mine | ForEach-Object { $_.Action = 'WouldRemove' } }
    }
}

# ------------------------------------------------------------ group-based licences
foreach ($g in $groupUse.Keys) {
    $uses = @($groupUse[$g] | Where-Object { $chosenIds.Contains($_.SkuId) })
    if (-not $uses) { continue }
    $grp = @{ displayName = $g }
    try { $grp = Invoke-MgGraphRequest GET "v1.0/groups/$($g)?`$select=id,displayName" } catch { Write-Verbose "Couldn't read group $g" }
    foreach ($skuGroup in ($uses | Group-Object SkuId)) {
        $id = $skuGroup.Name; $name = $skus[$id].skuPartNumber
        $blocked = @($skuGroup.Group | Where-Object { -not $_.InScope })
        $row = [pscustomobject]@{
            UserPrincipalName = "(group) $($grp.displayName)"; DisplayName = "$($skuGroup.Count) member(s) get it here"; Enabled = ''
            OnHold = ''; Licence = $name; AssignedBy = 'Group'; Action = ''; Detail = ''
        }
        if (-not $IncludeGroupLicences) { $row.Action = 'Skipped'; $row.Detail = 'Group licence: remove it from the group in the admin centre, or rerun with -IncludeGroupLicences' }
        elseif ($Users) { $row.Action = 'Skipped'; $row.Detail = 'Group licence and -Users was given: other members may still need it. Remove it from the group in the admin centre' }
        elseif ($blocked) { $row.Action = 'Skipped'; $row.Detail = "Also licenses skipped user(s): $(Get-First $blocked.User 5)" }
        elseif ($PSCmdlet.ShouldProcess("group $($grp.displayName): remove $name", 'Remove group licence')) {
            try {
                $body = @{ addLicenses = @(); removeLicenses = [string[]]@($id) } | ConvertTo-Json -Depth 4
                Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$g/assignLicense" -Body $body -ContentType 'application/json' | Out-Null
                $row.Action = 'Removed'; $row.Detail = 'Removed from the group; members lose it within minutes'
                Write-Host "  Removed  group $($grp.displayName): $name" -ForegroundColor Green
            }
            catch { $row.Action = 'Failed'; $row.Detail = $_.Exception.Message; Write-Host "  FAILED   group $($grp.displayName): $($_.Exception.Message)" -ForegroundColor Red }
        }
        else { $row.Action = 'WouldRemove' }
        $rows.Add($row)
    }
}

# ------------------------------------------------------------ subscriptions and the billing step for each
$customDomains = @(@((Invoke-MgGraphRequest GET 'v1.0/domains').value) | Where-Object { $_.id -notmatch '\.onmicrosoft\.com$' } | ForEach-Object { $_.id })
$skus = @{}
foreach ($s in @(Get-GraphAll 'v1.0/subscribedSkus')) { $skus["$($s.skuId)"] = $s }   # fresh used counts
$billing = @()
try {
    $billing = @(Get-GraphAll 'v1.0/directory/subscriptions' | Where-Object { $_.status -ne 'Deleted' } | ForEach-Object {
            $created = if ($_.createdDateTime) { [datetime]$_.createdDateTime } else { $null }
            $next = if ($_.nextLifecycleDateTime) { [datetime]$_.nextLifecycleDateTime } else { $null }
            $sku = $skus["$($_.skuId)"]
            $step = if ($_.status -in 'Warning', 'Suspended', 'LockedOut') { "Already lapsing ($($_.status)). Nothing to stop; make sure exports are done" }
            elseif ($_.isTrial) { 'Trial: turn off recurring billing, or it converts to paid' }
            elseif ($created -and ((Get-Date) - $created).TotalDays -le 7) { 'Started in the last 7 days: cancel it now for a refund' }
            else { "Turn off recurring billing so it ends on $(if ($next) { $next.ToString('yyyy-MM-dd') } else { 'its end date' }). Cancel instead only if it renewed in the last 7 days" }
            [pscustomobject]@{
                SkuPartNumber      = $_.skuPartNumber
                SubscriptionStatus = $_.status
                Trial              = $_.isTrial
                Seats              = $_.totalLicenses
                Used               = $(if ($sku) { $sku.consumedUnits } else { '' })
                Created            = $(if ($created) { $created.ToString('yyyy-MM-dd') } else { '' })
                EndsOrRenews       = $(if ($next) { $next.ToString('yyyy-MM-dd') } else { '' })
                NextStep           = $step
                CommerceId         = $_.commerceSubscriptionId
            } })
}
catch { Write-Warning "Couldn't read directory/subscriptions ($($_.Exception.Message)). Check Billing, Your products in the admin centre." }

# ------------------------------------------------------------ reports (written under -WhatIf too)
$file = ".\LicenceRemoval-$stamp.csv"
$billFile = ".\SubscriptionBilling-$stamp.csv"
if ($rows.Count) { $rows | Export-Csv $file -NoTypeInformation -WhatIf:$false }
if ($billing) { $billing | Export-Csv $billFile -NoTypeInformation -WhatIf:$false }

Write-Host ''
if ($rows.Count) {
    ($rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ' | ForEach-Object { Write-Host "Licences: $_. Report: $file" -ForegroundColor Cyan }
    $skipped = @($rows | Where-Object Action -eq 'Skipped')
    if ($skipped) { $skipped | Group-Object Detail | ForEach-Object { Write-Host ("  {0} skipped: {1}" -f $_.Count, $_.Name) -ForegroundColor Yellow } }
}
if ($billing) {
    Write-Host ''
    Write-Host 'Subscriptions: stop each one in the admin centre (Billing, Your products, the subscription), or ask your partner.' -ForegroundColor Cyan
    $billing | Format-Table SkuPartNumber, SubscriptionStatus, Seats, Used, EndsOrRenews, NextStep -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    Write-Host "Report: $billFile" -ForegroundColor Cyan
    Write-Host '  Admin centre: https://admin.microsoft.com/#/subscriptions' -ForegroundColor Gray
    Write-Host '  Bought through a partner (CSP)? The partner turns off auto-renew or cancels; the admin centre shows who sold it.' -ForegroundColor Gray
}
if ($customDomains) { Write-Warning "Custom domains still in the source: $($customDomains -join ', '). Remove them before the subscriptions end, or they stay tied to a tenant you can't easily get back into." }
if ($WhatIfPreference) { Write-Host 'Dry run (-WhatIf): nothing was changed. Run again without -WhatIf to remove.' -ForegroundColor Yellow }
Write-Host 'The CSVs list people: keep them out of source control.' -ForegroundColor Cyan
