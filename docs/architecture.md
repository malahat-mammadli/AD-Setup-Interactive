# Architecture & Design Notes

This document explains the structural decisions behind `setup_interactive.ps1` — how AD objects are organized, named, and related to each other.

---

## Overall Structure

```
Domain Root (e.g. DC=corp,DC=local)
└── [Top-level OU]          ← name chosen by user at runtime
    ├── [Department OU 1]
    │   ├── Users
    │   ├── Computers
    │   └── Groups
    ├── [Department OU 2]
    │   ├── Users
    │   ├── Computers
    │   └── Groups
    └── ...
```

All objects created by the script live under the single top-level OU. This makes cleanup, delegation, and GPO scoping straightforward.

---

## Organizational Units (OUs)

- **Top-level OU** — created first; name is provided by the user (e.g. `Departments`).
- **Department OUs** — one per department, nested directly inside the top-level OU.
- All OUs are created with `ProtectedFromAccidentalDeletion = $false` so the script can be re-run or cleaned up without manual intervention.

---

## Groups

Each department gets at least one security group:

| Group | Scope | Purpose |
|-------|-------|---------|
| `<CODE>_Users` | Global / Security | All regular users in the department |
| `<CODE>_Admins` | Global / Security | Privileged users (optional, chosen at runtime) |

**Naming convention:** `<CODE>` is the short department code provided by the user (e.g. `IT`, `FIN`, `HR`).

Groups are placed inside their department OU. Every user created for a department is automatically added to that department's `<CODE>_Users` group via `Add-ADGroupMember`.

---

## Users

- **Count** — set by the user: same count for all departments, or a custom count per department.
- **SamAccountName format** — `<CODE><globalIndex>` (e.g. `IT1`, `IT2`, `FIN301`). A global counter increments across all departments to guarantee uniqueness.
- **Name pool** — first and last names are drawn randomly from a combined Azerbaijani and English name pool to simulate a realistic, diverse user base.
- **UPN format** — `<SamAccountName>@<DomainFQDN>` (e.g. `IT1@corp.local`).
- **Password** — set from the secure string entered in Step 1. Never hardcoded.
- **ChangePasswordAtLogon** — set to `$false` for lab convenience; change to `$true` for production use.

---

## Computers

- **Count** — set by the user: same count for all departments, custom per department, or auto arithmetic series (base + step × index).
- **Naming format** — `<CODE>-<N>` where `<N>` is zero-padded based on the total count:
  - Up to 99 computers → 2-digit padding (`HR-01`)
  - Up to 999 computers → 3-digit padding (`HR-001`)
  - 1000+ computers → 4-digit padding (`HR-0001`)
- Computers are placed in their department OU and enabled by default.

---

## GPOs

GPOs are created and linked via the `New-EnsureGPO` helper function, which is idempotent — safe to run multiple times without creating duplicates.

**Password and lockout policies** are written as INF templates directly into SYSVOL (`GptTmpl.inf`). This is the correct method — applying these settings via `Set-GPRegistryValue` is silently ignored by Windows for account/password policy keys.

All other GPO settings (USB block, software restriction, logon banner, etc.) use `Set-GPRegistryValue`.

| GPO | Linked To | Method |
|-----|-----------|--------|
| `GPO-Domain-PasswordPolicy` | Domain root | INF / SYSVOL |
| `GPO-Domain-AccountLockout` | Domain root | INF / SYSVOL |
| `GPO-Domain-AuditPolicy` | Domain root | Registry |
| `GPO-Dept-USBBlock` | Top-level OU | Registry |
| `GPO-IT-StrictPassword` | IT dept OU | INF / SYSVOL |
| `GPO-IT-SoftwareRestriction` | IT dept OU | Registry |
| `GPO-FIN-DesktopRestriction` | Finance dept OU | Registry |
| `GPO-HR-LogonBanner` | HR dept OU | Registry |

---

## Fine-Grained Password Policy (PSO)

The PSO is applied directly to an AD group (not via GPO), which means it takes precedence over any domain-level password policy for members of that group.

All PSO settings are configurable at runtime:

| Setting | Default suggestion |
|---------|--------------------|
| Min password length | 12 |
| Max password age | 60 days |
| Password history | 10 |
| Lockout threshold | 5 attempts |
| Lockout duration | 30 minutes |
| Complexity | Enabled |
| Reversible encryption | Disabled |

**Precedence** is set to `10`, which gives it priority over the default domain policy (precedence 0 means no PSO).

---

## Idempotency

The script checks for existing objects before creating them:

- OUs — `Get-ADOrganizationalUnit -Filter`
- Groups — `Get-ADGroup -Filter`
- GPOs — `Get-GPO -Name`
- GPO links — catches the "already linked" exception
- PSO — `Get-ADFineGrainedPasswordPolicy -Filter`

Users and computers are always created fresh (they use a global incrementing index), so re-running the script will add more objects rather than skip them.

---

## Confirmation Gate

Before any AD changes are made, the script displays a full summary of all planned actions and requires explicit `Y` confirmation. This prevents accidental execution and gives the operator a final review opportunity.

---

## CSV Report

After setup, a summary CSV is exported with one row per department:

```
Department, Code, Groups, Users, Computers
Information Technology, IT, 2, 300, 140
Finance, FIN, 2, 300, 120
Human Resources, HR, 1, 300, 100
```

Default path: `C:\AD_Setup_Report.csv` (configurable at runtime).
