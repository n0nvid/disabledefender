# Disable Microsoft Defender on FlareVM

A one-shot PowerShell script that **permanently disables Microsoft Defender**
on a Windows malware-analysis VM (FlareVM).

> ⚠️ **For an isolated malware-analysis VM only.** Never run this on a
> production, personal, or internet-connected machine. Always keep the VM on a
> host-only / isolated network and take a snapshot before you start.

---

## Why the normal ways didn't work

On Windows 10 (2004+) and Windows 11, Defender fights back:

- The **Settings toggles are greyed out** because **Tamper Protection** is on.
- The old `DisableAntiSpyware` registry value is **ignored**.
- **Real-time protection turns itself back on** because the protected
  `WinDefend` service restarts, and Windows Update re-enables Tamper Protection.

This script kills all of that at once — including disabling the `WinDefend`
service (the part that actually makes it stick), which requires **Safe Mode**.

---

## Step-by-step

### 1. Snapshot the VM
Take a VM snapshot now so you can roll back if anything breaks.

### 2. Turn off Tamper Protection (by hand)
This is the one step that **cannot** be scripted — Microsoft blocks it.

1. Open **Windows Security**
2. Go to **Virus & threat protection**
3. Click **Manage settings**
4. Turn **Tamper Protection** to **Off**

### 3. Boot into Safe Mode
1. Press `Win + R`, type `msconfig`, press Enter
2. Go to the **Boot** tab
3. Check **Safe boot** (leave it on **Minimal**)
4. Click **OK** and **Restart**

### 4. Run the script as Administrator
1. In Safe Mode, click Start, type **PowerShell**
2. Right-click **Windows PowerShell** → **Run as administrator**
3. Change into this folder, e.g.:
   ```powershell
   cd C:\Tools\flarevm-disable-defender
   ```
4. Run it:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Disable-Defender.ps1
   ```
5. Watch the output — each service should print **[OK] ... Start=4 (disabled)**.

### 5. Leave Safe Mode
1. Open `msconfig` again
2. **Boot** tab → **uncheck** Safe boot
3. Click **OK** and **Restart**

### 6. Verify it worked
Open a normal (Administrator) PowerShell and run:
```powershell
Get-MpComputerStatus | Select RealTimeProtectionEnabled, AntivirusEnabled
```
Both should report **False**. You can also run `sc query WinDefend` — it should
show the service stopped and set to not start.

---

## What the script changes

| Layer | What it does |
|-------|--------------|
| `Set-MpPreference` | Turns off real-time, behavior, script, and archive scanning; disables cloud reporting |
| Policy registry keys | Sets `DisableAntiSpyware` / `DisableRealtimeMonitoring` under `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender` |
| Scheduled tasks | Disables all `\Microsoft\Windows\Windows Defender\` tasks |
| Services | Takes ownership of and sets `Start=4` (Disabled) on `WinDefend`, `Sense`, `WdNisSvc`, `WdNisDrv`, `WdFilter`, `WdBoot`, `SecurityHealthService` |
| Windows Update | Sets `NoAutoUpdate=1` so an update can't turn Tamper Protection / Defender back on |

---

## Undo

The clean way to undo is to **restore the VM snapshot** you took in step 1.
That's the whole reason for step 1.
