#Requires -Modules ActiveDirectory, GroupPolicy
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Interactive Active Directory setup script — OUs, Groups, Users, Computers, GPOs, PSO.

.DESCRIPTION
    Prompts the user for all configuration options (departments, user/computer counts,
    GPO and PSO preferences) then provisions the full AD environment accordingly.

.EXAMPLE
    .\setup_interactive.ps1

.NOTES
    Tested on Windows Server 2019/2022 with RSAT.
    Run as Domain Administrator.
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────
function Write-Header {
    param([string]$Text)
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host   "║  $Text" -ForegroundColor Cyan
    Write-Host   "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n  >> $Text" -ForegroundColor Yellow
}

function Read-PositiveInt {
    param([string]$Prompt, [int]$Min = 1, [int]$Max = 99999)
    while ($true) {
        $raw = Read-Host $Prompt
        if ($raw -match '^\d+$') {
            $val = [int]$raw
            if ($val -ge $Min -and $val -le $Max) { return $val }
        }
        Write-Host "  [!] Please enter a number between $Min and $Max." -ForegroundColor Red
    }
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $ans = Read-Host "$Prompt [Y/N]"
        if ($ans -match '^[Yy]$') { return $true  }
        if ($ans -match '^[Nn]$') { return $false }
        Write-Host "  [!] Please enter Y or N." -ForegroundColor Red
    }
}

function Read-NonEmpty {
    param([string]$Prompt)
    while ($true) {
        $val = (Read-Host $Prompt).Trim()
        if ($val -ne '') { return $val }
        Write-Host "  [!] This field cannot be empty." -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────
Clear-Host
Write-Host @"

  ╔══════════════════════════════════════════════════════════╗
  ║        ACTIVE DIRECTORY INTERACTIVE SETUP v3.0          ║
  ║   OUs · Groups · Users · Computers · GPOs · PSO         ║
  ╚══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────
# STEP 0 — Domain info
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 0 — Domain Detection"

try {
    $DomainDN   = (Get-ADDomain).DistinguishedName
    $DomainFQDN = (Get-ADDomain).DNSRoot
    Write-Host "  [✔] Domain detected : $DomainFQDN" -ForegroundColor Green
    Write-Host "      DN              : $DomainDN"
}
catch {
    Write-Error "Could not retrieve AD domain info. Are you running this on a DC or with RSAT?`n$_"
    exit 1
}

# ─────────────────────────────────────────────────────────────
# STEP 1 — Password
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 1 — Default User Password"
Write-Host "  This password will be assigned to all newly created users." -ForegroundColor Gray

$SecurePassword = Read-Host "  Enter default user password" -AsSecureString

# ─────────────────────────────────────────────────────────────
# STEP 2 — Top-level OU name
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 2 — Top-Level OU"
Write-Host "  All department OUs will be created inside this OU." -ForegroundColor Gray

$ParentOUName = Read-NonEmpty "  Top-level OU name (e.g. Departments)"

# ─────────────────────────────────────────────────────────────
# STEP 3 — Department definitions
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 3 — Departments"

$deptCount = Read-PositiveInt "  How many departments do you want to create?" -Min 1 -Max 100

$Depts = @()
Write-Host ""
for ($i = 1; $i -le $deptCount; $i++) {
    Write-Host "  --- Department $i of $deptCount ---" -ForegroundColor White
    $dName = Read-NonEmpty   "    Full name (e.g. Information Technology)"
    $dCode = Read-NonEmpty   "    Short code (e.g. IT)"
    $dCode = $dCode.ToUpper()
    $Depts += [PSCustomObject]@{ Name = $dName; Code = $dCode }
}

# ─────────────────────────────────────────────────────────────
# STEP 4 — Groups per department
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 4 — Groups per Department"
Write-Host "  Each department gets at least 1 group (<CODE>_Users)." -ForegroundColor Gray
Write-Host "  You can optionally add a second group (<CODE>_Admins) per department." -ForegroundColor Gray
Write-Host ""

$GroupsPerDept = @{}
$addAdminsToAll = Read-YesNo "  Add an Admins group to ALL departments?"

foreach ($dept in $Depts) {
    if ($addAdminsToAll) {
        $GroupsPerDept[$dept.Code] = 2
    } else {
        $addAdmins = Read-YesNo "  Add Admins group for '$($dept.Name)' ($($dept.Code))?"
        $GroupsPerDept[$dept.Code] = if ($addAdmins) { 2 } else { 1 }
    }
}

# ─────────────────────────────────────────────────────────────
# STEP 5 — User counts
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 5 — User Counts"

$userMode = ""
while ($userMode -notin @("1","2")) {
    Write-Host "  How would you like to set user counts?" -ForegroundColor White
    Write-Host "    [1] Same number for all departments"
    Write-Host "    [2] Custom number per department"
    $userMode = (Read-Host "  Your choice").Trim()
}

$UserCounts = @{}
if ($userMode -eq "1") {
    $sameCount = Read-PositiveInt "  Users per department" -Min 0 -Max 99999
    foreach ($dept in $Depts) { $UserCounts[$dept.Code] = $sameCount }
} else {
    foreach ($dept in $Depts) {
        $UserCounts[$dept.Code] = Read-PositiveInt "  Users for '$($dept.Name)' ($($dept.Code))" -Min 0 -Max 99999
    }
}

$TotalUsers = ($UserCounts.Values | Measure-Object -Sum).Sum
Write-Host "  [✔] Total users to create: $TotalUsers" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────
# STEP 6 — Computer counts
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 6 — Computer Counts"

$compMode = ""
while ($compMode -notin @("1","2","3")) {
    Write-Host "  How would you like to set computer counts?" -ForegroundColor White
    Write-Host "    [1] Same number for all departments"
    Write-Host "    [2] Custom number per department"
    Write-Host "    [3] Auto (arithmetic series — unique count per dept)"
    $compMode = (Read-Host "  Your choice").Trim()
}

$CompCounts = @{}
if ($compMode -eq "1") {
    $sameComp = Read-PositiveInt "  Computers per department" -Min 0 -Max 99999
    foreach ($dept in $Depts) { $CompCounts[$dept.Code] = $sameComp }
}
elseif ($compMode -eq "2") {
    foreach ($dept in $Depts) {
        $CompCounts[$dept.Code] = Read-PositiveInt "  Computers for '$($dept.Name)' ($($dept.Code))" -Min 0 -Max 99999
    }
}
else {
    # Arithmetic series: base + step * index
    $compBase = Read-PositiveInt "  Starting count for first department (base)" -Min 1 -Max 9999
    $compStep = Read-PositiveInt "  Increment per department (step)"            -Min 0 -Max 999
    for ($i = 0; $i -lt $Depts.Count; $i++) {
        $CompCounts[$Depts[$i].Code] = $compBase + ($i * $compStep)
    }
    $totalComp = ($CompCounts.Values | Measure-Object -Sum).Sum
    Write-Host "  [✔] Total computers to create (auto): $totalComp" -ForegroundColor Green
}

$TotalComputers = ($CompCounts.Values | Measure-Object -Sum).Sum
Write-Host "  [✔] Total computers to create: $TotalComputers" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────
# STEP 7 — GPOs
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 7 — Group Policy Objects (GPOs)"

$createGPOs = Read-YesNo "  Create and link GPOs?"

$GPOConfig = @{
    CreateGPOs          = $createGPOs
    PasswordPolicy      = $false
    AccountLockout      = $false
    AuditPolicy         = $false
    USBBlock            = $false
    ITStrictPassword    = $false
    ITSoftwareRestrict  = $false
    FINDesktopRestrict  = $false
    HRLogonBanner       = $false
    ITDeptCode          = ""
    FINDeptCode         = ""
    HRDeptCode          = ""
}

if ($createGPOs) {
    Write-Host ""
    Write-Host "  Select which GPOs to create:" -ForegroundColor White

    $GPOConfig.PasswordPolicy     = Read-YesNo "    [1] Domain Password Policy (min password length)"
    $GPOConfig.AccountLockout     = Read-YesNo "    [2] Domain Account Lockout Policy"
    $GPOConfig.AuditPolicy        = Read-YesNo "    [3] Domain Audit Policy (Security event log)"
    $GPOConfig.USBBlock           = Read-YesNo "    [4] USB Storage Block (all departments)"

    $GPOConfig.ITStrictPassword   = Read-YesNo "    [5] IT Strict Password Policy (min 12 chars)"
    if ($GPOConfig.ITStrictPassword) {
        $GPOConfig.ITDeptCode = Read-NonEmpty "        Enter IT department code (e.g. IT)"
    }

    $GPOConfig.ITSoftwareRestrict = Read-YesNo "    [6] IT Software Restriction Policy"
    if ($GPOConfig.ITSoftwareRestrict -and $GPOConfig.ITDeptCode -eq "") {
        $GPOConfig.ITDeptCode = Read-NonEmpty "        Enter IT department code (e.g. IT)"
    }

    $GPOConfig.FINDesktopRestrict = Read-YesNo "    [7] Finance Desktop Restriction (no Control Panel + USB block)"
    if ($GPOConfig.FINDesktopRestrict) {
        $GPOConfig.FINDeptCode = Read-NonEmpty "        Enter Finance department code (e.g. FIN)"
    }

    $GPOConfig.HRLogonBanner      = Read-YesNo "    [8] HR Legal Logon Banner"
    if ($GPOConfig.HRLogonBanner) {
        $GPOConfig.HRDeptCode = Read-NonEmpty "        Enter HR department code (e.g. HR)"
    }
}

# ─────────────────────────────────────────────────────────────
# STEP 8 — PSO
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 8 — Fine-Grained Password Policy (PSO)"

$createPSO  = Read-YesNo "  Create a Fine-Grained Password Policy (PSO)?"
$PSOConfig  = @{
    Create    = $createPSO
    Name      = ""
    Group     = ""
    MinLength = 12
    MaxAge    = 60
    History   = 10
    Lockout   = 5
    Duration  = 30
}

if ($createPSO) {
    $PSOConfig.Name      = Read-NonEmpty    "    PSO name (e.g. PSO-IT-StrictPassword)"
    $PSOConfig.Group     = Read-NonEmpty    "    Apply to which AD group? (e.g. IT_Users)"
    $PSOConfig.MinLength = Read-PositiveInt "    Minimum password length" -Min 6 -Max 128
    $PSOConfig.MaxAge    = Read-PositiveInt "    Maximum password age (days)" -Min 1 -Max 999
    $PSOConfig.History   = Read-PositiveInt "    Password history count" -Min 0 -Max 24
    $PSOConfig.Lockout   = Read-PositiveInt "    Lockout threshold (failed attempts)" -Min 0 -Max 99
    $PSOConfig.Duration  = Read-PositiveInt "    Lockout duration (minutes)" -Min 1 -Max 9999
}

# ─────────────────────────────────────────────────────────────
# STEP 9 — CSV report path
# ─────────────────────────────────────────────────────────────
Write-Header "STEP 9 — Report"

$defaultCsv = "C:\AD_Setup_Report.csv"
Write-Host "  A CSV summary will be saved after setup completes." -ForegroundColor Gray
$csvInput = (Read-Host "  CSV report path [default: $defaultCsv]").Trim()
$CsvReportPath = if ($csvInput -eq '') { $defaultCsv } else { $csvInput }

# ─────────────────────────────────────────────────────────────
# CONFIRMATION SUMMARY
# ─────────────────────────────────────────────────────────────
Write-Header "CONFIRMATION SUMMARY"

Write-Host "  Domain          : $DomainFQDN"
Write-Host "  Top-level OU    : $ParentOUName"
Write-Host "  Departments     : $($Depts.Count)"
Write-Host "  Total Users     : $TotalUsers"
Write-Host "  Total Computers : $TotalComputers"
Write-Host "  GPOs            : $(if ($GPOConfig.CreateGPOs) { 'Yes' } else { 'No' })"
Write-Host "  PSO             : $(if ($PSOConfig.Create) { $PSOConfig.Name } else { 'No' })"
Write-Host "  CSV Report      : $CsvReportPath"
Write-Host ""
Write-Host "  Departments to create:" -ForegroundColor White
foreach ($dept in $Depts) {
    $g = $GroupsPerDept[$dept.Code]
    $u = $UserCounts[$dept.Code]
    $c = $CompCounts[$dept.Code]
    Write-Host ("    {0,-35} Code: {1,-6}  Groups: {2}  Users: {3}  Computers: {4}" -f $dept.Name, $dept.Code, $g, $u, $c)
}

Write-Host ""
$confirm = Read-YesNo "  Proceed with setup?"
if (-not $confirm) {
    Write-Host "`n  [!] Setup cancelled by user." -ForegroundColor Red
    exit 0
}

# ─────────────────────────────────────────────────────────────
# EXECUTION — Top-level OU
# ─────────────────────────────────────────────────────────────
Write-Header "RUNNING — Creating AD Structure"

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ParentOUName'" `
        -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $ParentOUName -Path $DomainDN `
        -ProtectedFromAccidentalDeletion $false
    Write-Host "  [+] OU created : $ParentOUName" -ForegroundColor Green
} else {
    Write-Host "  [~] OU exists  : $ParentOUName" -ForegroundColor DarkGray
}

$ParentPath = "OU=$ParentOUName,$DomainDN"

# ─────────────────────────────────────────────────────────────
# Name pools
# ─────────────────────────────────────────────────────────────
$FirstNames = @(
    "Adil","Aydin","Elvin","Rashad","Tural","Kamal","Murad","Orkhan","Samir","Vugar",
    "Emil","Nijat","Farid","Emin","Ilgar","Rauf","Elnur","Firdovsi","Kamran","Cavid",
    "Aysel","Nigar","Gunel","Leyla","Sabina","Jale","Laman","Aydan","Amina","Zahra",
    "Narmin","Aynur","Sevda","Mehriban","Ulker","Sevinc","Gunay","Afaq","Turkan","Narmina",
    "James","Mary","Robert","Patricia","John","Jennifer","Michael","Linda","William","Barbara",
    "David","Susan","Richard","Jessica","Joseph","Sarah","Thomas","Karen","Charles","Nancy",
    "Daniel","Lisa","Matthew","Betty","Anthony","Margaret","Mark","Sandra","Donald","Ashley",
    "Steven","Dorothy","Paul","Kimberly","Andrew","Emily","Joshua","Donna","Kenneth","Michelle",
    "Kevin","Carol","Brian","Amanda","George","Melissa","Edward","Deborah","Ronald","Stephanie",
    "Timothy","Rebecca","Jason","Sharon","Jeffrey","Laura","Ryan","Cynthia","Jacob","Kathleen"
)

$LastNames = @(
    "Aliyev","Mammadov","Huseynov","Ibrahimov","Hasanov","Quliyev","Rzayev","Abbasov",
    "Karimov","Mustafayev","Jafarov","Babayev","Hajiyev","Ismayilov","Niftaliyev",
    "Asgarov","Mirzayev","Guliyev","Aghayev","Tahirov","Rahmanov","Suleymanov",
    "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
    "Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson","Anderson","Thomas",
    "Taylor","Moore","Jackson","Martin","Lee","Perez","Thompson","White",
    "Harris","Sanchez","Clark","Lewis","Robinson","Walker","Young","Hall"
)

# ─────────────────────────────────────────────────────────────
# Main loop — OUs, Groups, Users, Computers
# ─────────────────────────────────────────────────────────────
$uGlobal = 1

for ($d = 0; $d -lt $Depts.Count; $d++) {
    $dept  = $Depts[$d]
    $code  = $dept.Code
    $ouDN  = "OU=$($dept.Name),$ParentPath"

    Write-Step "[$($d+1)/$($Depts.Count)] $($dept.Name) (Code: $code)"

    # ── OU ──────────────────────────────────────────────────
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($dept.Name)'" `
            -SearchBase $ParentPath -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $dept.Name -Path $ParentPath `
            -ProtectedFromAccidentalDeletion $false
        Write-Host "    [+] OU created : $($dept.Name)" -ForegroundColor Green
    } else {
        Write-Host "    [~] OU exists  : $($dept.Name)" -ForegroundColor DarkGray
    }

    # ── Groups ──────────────────────────────────────────────
    for ($g = 1; $g -le $GroupsPerDept[$code]; $g++) {
        $suffix  = if ($g -eq 1) { "Users" } else { "Admins" }
        $grpName = "${code}_${suffix}"
        if (-not (Get-ADGroup -Filter "Name -eq '$grpName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $grpName -GroupScope Global -GroupCategory Security `
                -Path $ouDN -Description "$($dept.Name) - $suffix"
            Write-Host "    [+] Group: $grpName" -ForegroundColor Green
        } else {
            Write-Host "    [~] Group exists: $grpName" -ForegroundColor DarkGray
        }
    }

    # ── Users ───────────────────────────────────────────────
    $uCount = $UserCounts[$code]
    Write-Host "    Users to create: $uCount" -ForegroundColor White

    $createdInDept = 0
    while ($createdInDept -lt $uCount) {
        $fn  = $FirstNames | Get-Random
        $ln  = $LastNames  | Get-Random
        $sam = "${code}${uGlobal}"
        if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }

        try {
            New-ADUser `
                -Name                  "$fn $ln" `
                -GivenName             $fn `
                -Surname               $ln `
                -SamAccountName        $sam `
                -UserPrincipalName     "$sam@$DomainFQDN" `
                -AccountPassword       $SecurePassword `
                -Path                  $ouDN `
                -Enabled               $true `
                -ChangePasswordAtLogon $false `
                -Department            $dept.Name

            Add-ADGroupMember -Identity "${code}_Users" -Members $sam -ErrorAction SilentlyContinue
            $createdInDept++
            $uGlobal++
        }
        catch {
            Write-Warning "    Skipped $sam : $_"
            $uGlobal++
        }
    }
    Write-Host "    [✔] $createdInDept users created" -ForegroundColor Green

    # ── Computers ───────────────────────────────────────────
    $cCount  = $CompCounts[$code]
    $padding = if ($cCount -ge 1000) { 4 } elseif ($cCount -ge 100) { 3 } else { 2 }
    Write-Host "    Computers to create: $cCount" -ForegroundColor White

    for ($c = 1; $c -le $cCount; $c++) {
        $cn = "$code-$($c.ToString("D$padding"))"
        try {
            New-ADComputer -Name $cn -Path $ouDN -Enabled $true `
                -Description "Workstation - $($dept.Name)"
        }
        catch { Write-Warning "    Computer $cn : $_" }
    }
    Write-Host "    [✔] $cCount computers created" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# GPO HELPERS
# ─────────────────────────────────────────────────────────────
function New-EnsureGPO {
    param([string]$Name, [string]$TargetDN, [string]$Comment)

    if (-not (Get-GPO -Name $Name -ErrorAction SilentlyContinue)) {
        New-GPO -Name $Name -Comment $Comment | Out-Null
        Write-Host "  [+] GPO created : $Name" -ForegroundColor Green
    } else {
        Write-Host "  [~] GPO exists  : $Name" -ForegroundColor DarkGray
    }

    try {
        New-GPLink -Name $Name -Target $TargetDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
        Write-Host "  [+] Linked      : $Name → $TargetDN" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -match "already") {
            Write-Host "  [~] Link exists : $Name → $TargetDN" -ForegroundColor DarkGray
        } else {
            Write-Warning "  Link failed: $Name → $TargetDN : $_"
        }
    }
    return Get-GPO -Name $Name
}

function Set-GPPasswordPolicy {
    param(
        [Microsoft.GroupPolicy.Gpo]$Gpo,
        [int]$MinLength,
        [int]$MaxAge            = 90,
        [int]$MinAge            = 1,
        [int]$History           = 10,
        [bool]$Complexity       = $true,
        [int]$LockoutThreshold  = 5,
        [int]$LockoutDuration   = 30,
        [int]$LockoutWindow     = 30
    )

    $gpoGuid = $Gpo.Id.ToString("B")
    $sysvol  = "\\$DomainFQDN\SYSVOL\$DomainFQDN\Policies\$gpoGuid\Machine\Microsoft\Windows NT\SecEdit"

    if (-not (Test-Path $sysvol)) {
        New-Item -ItemType Directory -Path $sysvol -Force | Out-Null
    }

    $cVal = if ($Complexity) { 1 } else { 0 }
    @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordLength = $MinLength
MaximumPasswordAge    = $MaxAge
MinimumPasswordAge    = $MinAge
PasswordHistorySize   = $History
PasswordComplexity    = $cVal
LockoutBadCount       = $LockoutThreshold
LockoutDuration       = $LockoutDuration
ResetLockoutCount     = $LockoutWindow
[Version]
signature="`$CHICAGO`$"
Revision=1
"@ | Out-File -FilePath (Join-Path $sysvol "GptTmpl.inf") -Encoding Unicode -Force

    Write-Host "  [+] Password policy INF written for: $($Gpo.DisplayName)" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# GPO CREATION
# ─────────────────────────────────────────────────────────────
if ($GPOConfig.CreateGPOs) {
    Write-Header "RUNNING — GPOs"

    $itOU  = if ($GPOConfig.ITDeptCode  -ne "") { "OU=$($Depts | Where-Object Code -eq $GPOConfig.ITDeptCode  | Select-Object -ExpandProperty Name),$ParentPath" } else { $null }
    $finOU = if ($GPOConfig.FINDeptCode -ne "") { "OU=$($Depts | Where-Object Code -eq $GPOConfig.FINDeptCode | Select-Object -ExpandProperty Name),$ParentPath" } else { $null }
    $hrOU  = if ($GPOConfig.HRDeptCode  -ne "") { "OU=$($Depts | Where-Object Code -eq $GPOConfig.HRDeptCode  | Select-Object -ExpandProperty Name),$ParentPath" } else { $null }

    if ($GPOConfig.PasswordPolicy) {
        $gpo = New-EnsureGPO "GPO-Domain-PasswordPolicy" $DomainDN "Domain: minimum password length policy"
        Set-GPPasswordPolicy -Gpo $gpo -MinLength 8 -LockoutThreshold 0
    }

    if ($GPOConfig.AccountLockout) {
        $gpo = New-EnsureGPO "GPO-Domain-AccountLockout" $DomainDN "Domain: lockout after 5 failed attempts"
        Set-GPPasswordPolicy -Gpo $gpo -MinLength 8 -LockoutThreshold 5 -LockoutDuration 30 -LockoutWindow 30
    }

    if ($GPOConfig.AuditPolicy) {
        $gpo = New-EnsureGPO "GPO-Domain-AuditPolicy" $DomainDN "Domain: security event log settings"
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security" `
            -ValueName "MaxSize" -Type DWord -Value 32768 -ErrorAction SilentlyContinue
    }

    if ($GPOConfig.USBBlock) {
        $gpo = New-EnsureGPO "GPO-Dept-USBBlock" $ParentPath "All departments: block USB removable storage"
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR" `
            -ValueName "Start" -Type DWord -Value 4 -ErrorAction SilentlyContinue
    }

    if ($GPOConfig.ITStrictPassword -and $itOU) {
        $gpo = New-EnsureGPO "GPO-IT-StrictPassword" $itOU "IT dept: min 12-char password"
        Set-GPPasswordPolicy -Gpo $gpo -MinLength 12 -Complexity $true
    }

    if ($GPOConfig.ITSoftwareRestrict -and $itOU) {
        $gpo = New-EnsureGPO "GPO-IT-SoftwareRestriction" $itOU "IT dept: restrict unauthorized software"
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers" `
            -ValueName "DefaultLevel" -Type DWord -Value 131072 -ErrorAction SilentlyContinue
    }

    if ($GPOConfig.FINDesktopRestrict -and $finOU) {
        $gpo = New-EnsureGPO "GPO-FIN-DesktopRestriction" $finOU "Finance: disable Control Panel and USB storage"
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
            -ValueName "NoControlPanel" -Type DWord -Value 1 -ErrorAction SilentlyContinue
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR" `
            -ValueName "Start" -Type DWord -Value 4 -ErrorAction SilentlyContinue
    }

    if ($GPOConfig.HRLogonBanner -and $hrOU) {
        $gpo = New-EnsureGPO "GPO-HR-LogonBanner" $hrOU "HR: legal logon notice banner"
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "LegalNoticeCaption" -Type String -Value "Authorized Access Only" -ErrorAction SilentlyContinue
        Set-GPRegistryValue -Name $gpo.DisplayName `
            -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "LegalNoticeText" -Type String `
            -Value "This system is for authorized personnel only. Unauthorized access is prohibited and may be prosecuted." `
            -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────
# PSO CREATION
# ─────────────────────────────────────────────────────────────
if ($PSOConfig.Create) {
    Write-Header "RUNNING — Fine-Grained Password Policy (PSO)"

    try {
        if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$($PSOConfig.Name)'" -ErrorAction SilentlyContinue)) {
            New-ADFineGrainedPasswordPolicy `
                -Name                        $PSOConfig.Name `
                -Precedence                  10 `
                -MinPasswordLength           $PSOConfig.MinLength `
                -PasswordHistoryCount        $PSOConfig.History `
                -ComplexityEnabled           $true `
                -LockoutThreshold            $PSOConfig.Lockout `
                -LockoutDuration             "0:$($PSOConfig.Duration):00" `
                -LockoutObservationWindow    "0:$($PSOConfig.Duration):00" `
                -MaxPasswordAge              "$($PSOConfig.MaxAge).00:00:00" `
                -MinPasswordAge              "1.00:00:00" `
                -ReversibleEncryptionEnabled $false
            Write-Host "  [+] PSO created: $($PSOConfig.Name)" -ForegroundColor Green
        } else {
            Write-Host "  [~] PSO exists : $($PSOConfig.Name)" -ForegroundColor DarkGray
        }

        $targetGroup = Get-ADGroup -Filter "Name -eq '$($PSOConfig.Group)'" -ErrorAction SilentlyContinue
        if ($targetGroup) {
            Add-ADFineGrainedPasswordPolicySubject -Identity $PSOConfig.Name -Subjects $PSOConfig.Group -ErrorAction SilentlyContinue
            Write-Host "  [+] PSO applied to: $($PSOConfig.Group)" -ForegroundColor Green
        } else {
            Write-Warning "  Group '$($PSOConfig.Group)' not found — PSO not applied."
        }
    }
    catch { Write-Warning "PSO setup failed: $_" }
}

# ─────────────────────────────────────────────────────────────
# SUMMARY & CSV
# ─────────────────────────────────────────────────────────────
Write-Header "SETUP COMPLETE — Summary"

Write-Host "  Domain          : $DomainFQDN"
Write-Host "  OUs             : $((Get-ADOrganizationalUnit -Filter * -SearchBase $ParentPath).Count)"
Write-Host "  Groups          : $((Get-ADGroup             -Filter * -SearchBase $ParentPath).Count)"
Write-Host "  Users           : $((Get-ADUser              -Filter * -SearchBase $ParentPath).Count)"
Write-Host "  Computers       : $((Get-ADComputer          -Filter * -SearchBase $ParentPath).Count)"
if ($GPOConfig.CreateGPOs) {
    Write-Host "  GPOs (domain)   : $((Get-GPO -All).Count)"
}

Write-Host ""
Write-Host ("  {0,-35} {1,-6} {2,-7} {3,-8} {4}" -f "Department","Code","Groups","Users","Computers") -ForegroundColor White
Write-Host ("  " + "-" * 65)
foreach ($dept in $Depts) {
    Write-Host ("  {0,-35} {1,-6} {2,-7} {3,-8} {4}" -f `
        $dept.Name, $dept.Code, $GroupsPerDept[$dept.Code], $UserCounts[$dept.Code], $CompCounts[$dept.Code])
}

# Export CSV
$report = foreach ($dept in $Depts) {
    [PSCustomObject]@{
        Department = $dept.Name
        Code       = $dept.Code
        Groups     = $GroupsPerDept[$dept.Code]
        Users      = $UserCounts[$dept.Code]
        Computers  = $CompCounts[$dept.Code]
    }
}
$report | Export-Csv $CsvReportPath -NoTypeInformation -Encoding UTF8
Write-Host "`n  [✔] CSV report saved: $CsvReportPath" -ForegroundColor Green
Write-Host "`n  === AD Interactive Setup Complete ===" -ForegroundColor Cyan
