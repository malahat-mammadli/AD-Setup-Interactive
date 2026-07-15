# 🏢 AD-Setup — Interactive Active Directory Provisioning Script

A fully interactive PowerShell script that provisions an entire Active Directory environment through a step-by-step wizard. No hardcoded values — everything is configured at runtime.

---

## ⚠️ Legal & Safety Notice

> **Only run this script on systems you own or have explicit written authorization to administer.**
> This script creates a large number of AD objects. Test in a lab environment before running in production.
> **Never run on a live production domain without a full backup.**

---

## 🧩 What Gets Created

| Object | Details |
|--------|---------|
| **Top-level OU** | Container for all department OUs (name you choose) |
| **Department OUs** | One per department, nested inside top-level OU |
| **Security Groups** | `<CODE>_Users` per dept + optional `<CODE>_Admins` |
| **Users** | Random names from Azerbaijani + English name pools, added to `<CODE>_Users` |
| **Computers** | Named `<CODE>-001`, `<CODE>-002`… placed in dept OU |
| **GPOs** | Up to 8 pre-built policies, selectable at runtime |
| **PSO** | Fine-Grained Password Policy applied to any group you choose |
| **CSV Report** | Full summary exported after setup completes |

---

## 📋 Requirements

| Requirement | Detail |
|-------------|--------|
| OS | Windows Server 2016 / 2019 / 2022 |
| Role | Active Directory Domain Services (AD DS) |
| Feature | Group Policy Management (GPMC) |
| PowerShell | 5.1 or later |
| Run as | Domain Administrator |

---

## 🚀 Quick Start

```powershell
# Clone the repo
git clone https://github.com/malahat-mammadli/AD-Setup-Interactive.git
cd AD-Setup-Interactive

# Run the interactive wizard
.\setup_interactive.ps1
```

The script will guide you through 9 steps before making any changes.

---

## 🧭 Setup Wizard — Step by Step

### Step 0 — Domain Detection
The script automatically detects your domain FQDN and Distinguished Name via `Get-ADDomain`. No input needed.

### Step 1 — Default User Password
Sets the initial password for all created user accounts. You are prompted securely (`-AsSecureString`). Passwords are never stored in the script or repository.

### Step 2 — Top-Level OU
Name of the parent OU that will contain all department OUs.
```
Example: Departments
```

### Step 3 — Departments
Enter how many departments to create, then provide a full name and short code for each.
```
Department 1 of 3:
  Full name : Information Technology
  Short code: IT

Department 2 of 3:
  Full name : Finance
  Short code: FIN
```

### Step 4 — Groups
Choose whether to add an `<CODE>_Admins` group in addition to the default `<CODE>_Users` group — either for all departments at once or individually.

### Step 5 — User Counts
Choose one of:
- **Same number** for all departments
- **Custom number** per department

### Step 6 — Computer Counts
Choose one of:
- **Same number** for all departments
- **Custom number** per department
- **Auto (arithmetic series)** — provide a base count and a step value; each department gets a unique count

```
Example: base=100, step=20
  Dept 1 → 100 computers
  Dept 2 → 120 computers
  Dept 3 → 140 computers
```

### Step 7 — GPOs
Choose which of the 8 pre-built GPOs to create and link:

| # | GPO | Scope |
|---|-----|-------|
| 1 | `GPO-Domain-PasswordPolicy` | Domain — min password length |
| 2 | `GPO-Domain-AccountLockout` | Domain — lockout after 5 attempts |
| 3 | `GPO-Domain-AuditPolicy` | Domain — security event log size |
| 4 | `GPO-Dept-USBBlock` | All departments — block USB storage |
| 5 | `GPO-IT-StrictPassword` | IT OU — min 12-char password |
| 6 | `GPO-IT-SoftwareRestriction` | IT OU — software restriction policy |
| 7 | `GPO-FIN-DesktopRestriction` | Finance OU — no Control Panel + USB block |
| 8 | `GPO-HR-LogonBanner` | HR OU — legal notice at logon |

> Password and lockout policies are applied via INF templates written directly to SYSVOL — the correct method for these settings, which are silently ignored when applied via registry keys.

### Step 8 — Fine-Grained Password Policy (PSO)
Optionally create a PSO with fully configurable settings:

| Setting | You provide |
|---------|------------|
| PSO name | e.g. `PSO-IT-StrictPassword` |
| Target group | e.g. `IT_Users` |
| Min password length | e.g. `12` |
| Max password age (days) | e.g. `60` |
| Password history count | e.g. `10` |
| Lockout threshold | e.g. `5` |
| Lockout duration (minutes) | e.g. `30` |

### Step 9 — CSV Report Path
Where to save the summary report after setup. Defaults to `C:\AD_Setup_Report.csv`.

---

## ✅ Confirmation Screen

Before any AD objects are created, the script displays a full summary and asks for confirmation:

```
  Domain          : corp.local
  Top-level OU    : Departments
  Departments     : 3
  Total Users     : 900
  Total Computers : 360
  GPOs            : Yes
  PSO             : PSO-IT-StrictPassword
  CSV Report      : C:\AD_Setup_Report.csv

  Departments to create:
    Information Technology       Code: IT     Groups: 2  Users: 300  Computers: 140
    Finance                      Code: FIN    Groups: 2  Users: 300  Computers: 120
    Human Resources              Code: HR     Groups: 1  Users: 300  Computers: 100

  Proceed with setup? [Y/N]:
```

---

## 📄 Output

After setup, a CSV report is saved with one row per department:

| Column | Description |
|--------|-------------|
| Department | Full department name |
| Code | Short code |
| Groups | Number of groups created |
| Users | Number of users created |
| Computers | Number of computers created |

---

## 🔒 Security Notes

- Passwords are **never stored** in the script or repository
- `.gitignore` excludes `*.csv`, `*.log`, and any `*secret*` / `*password*` files
- Run only on a **domain controller or admin workstation** with RSAT installed
- Always test in a **lab environment** before running in production
- Review GPO settings before applying to a real domain

---

## 📁 Repository Structure

```
AD-Setup/
├── setup_interactive.ps1       # Main interactive wizard script
├── README.md                   # This file
├── .gitignore                  # Excludes logs, CSVs, secrets
├── LICENSE                     # MIT License
└── docs/
    ├── architecture.md         # OU / Group / User design notes
    └── gpo-reference.md        # GPO details and registry keys
```

---

## 🤝 Contributing

Pull requests are welcome. To add a new GPO option:
1. Add a `Read-YesNo` prompt in the Step 7 section
2. Add the corresponding config key to `$GPOConfig`
3. Add the GPO creation block in the GPO execution section
4. Update `docs/gpo-reference.md`

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.
