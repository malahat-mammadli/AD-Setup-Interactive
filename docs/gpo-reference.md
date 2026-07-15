# GPO Reference

## Why INF templates instead of Set-GPRegistryValue for password policies?

Windows stores **Account Policies** (password length, lockout, Kerberos) in
`Security Settings`, not in the registry hive. When you call `Set-GPRegistryValue`
on `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\MinimumPasswordLength`,
Windows reads and displays the value — but the **Security Configuration Engine**
ignores it entirely at policy application time.

The correct path is to write a `GptTmpl.inf` file into the GPO's SYSVOL folder
under `Machine\Microsoft\Windows NT\SecEdit\`. This is exactly what the
`Set-GPPasswordPolicy` helper function in `setup.ps1` does.

---

## GPO Details

### GPO-Domain-PasswordPolicy
- **Scope**: Domain root  
- **Method**: INF template (GptTmpl.inf)  
- **Settings**: MinPasswordLength=8, no lockout  

### GPO-Domain-AccountLockout
- **Scope**: Domain root  
- **Method**: INF template (GptTmpl.inf)  
- **Settings**: LockoutBadCount=5, LockoutDuration=30 min, ResetLockoutCount=30 min  

### GPO-Domain-AuditPolicy
- **Scope**: Domain root  
- **Method**: Registry (Security EventLog MaxSize)  
- **Key**: `HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security`  
- **Value**: MaxSize = 32768 (KB)  

### GPO-IT-StrictPassword
- **Scope**: IT OU  
- **Method**: INF template (GptTmpl.inf)  
- **Settings**: MinPasswordLength=12, Complexity=1  
- **Note**: Superseded in practice by PSO-IT-StrictPassword (Fine-Grained PSO has higher precedence)  

### GPO-IT-SoftwareRestriction
- **Scope**: IT OU  
- **Key**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers`  
- **Value**: DefaultLevel = 131072 (Disallowed)  

### GPO-FIN-DesktopRestriction
- **Scope**: Finance OU  
- **Keys**:  
  - `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` → NoControlPanel = 1  
  - `HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR` → Start = 4 (Disabled)  

### GPO-HR-LogonBanner
- **Scope**: HR OU  
- **Key**: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`  
- **Values**: LegalNoticeCaption, LegalNoticeText  

### GPO-Dept-USBBlock
- **Scope**: Departments OU (all depts)  
- **Key**: `HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR`  
- **Value**: Start = 4 (Disabled)  

---

## Fine-Grained Password Policy (PSO)

PSOs are **not GPOs**. They are AD objects stored in
`CN=Password Settings Container,CN=System,DC=...` and applied directly to
users or groups — bypassing GPO entirely.

`PSO-IT-StrictPassword` (Precedence 10) is applied to the **IT_Users** group.
When multiple PSOs apply to a user, the one with the **lowest Precedence number** wins.
