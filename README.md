# Disabling Microsoft Defender on FlareVM — The Definitive Guide

A complete, repeatable procedure to disable Microsoft Defender **for good** on a
Windows malware-analysis VM (FlareVM), plus the `Disable-Defender.ps1` script
that does the heavy lifting.

> ⚠️ **Isolated analysis VM only.** Everything here assumes a disposable,
> snapshotted VM on an **isolated / host-only network**. Never run any of this on
> a production, personal, or internet-connected Windows install. A machine with
> Defender off and live malware on it is only safe because it's sandboxed.

---

## TL;DR (the order that actually works)

1. **Snapshot** the clean VM.
2. **Disconnect the VM from the internet** (host-only adapter) and **disable
   Windows Update** — this is the step people skip, and it's *why Defender keeps
   coming back*.
3. **Turn off Tamper Protection** by hand in the UI (can't be scripted).
4. **Boot into Safe Mode.**
5. Run **`Disable-Defender.ps1`** as Administrator.
6. **Leave Safe Mode**, reboot, **verify**, then **take a new snapshot** of the
   "Defender-off" state.
7. *Then* install / use FlareVM.

If you do all of these, it stays dead. If you only do some, it resurrects.

---

## Why Defender keeps turning itself back on

Modern Windows 10 (2004+) and Windows 11 actively fight you:

| What you tried | Why it failed |
|----------------|---------------|
| Settings toggles | Greyed out by **Tamper Protection** |
| `DisableAntiSpyware` registry value | **Ignored** since Win10 2004 |
| `Set-MpPreference -DisableRealtimeMonitoring` | Reverts on reboot while Tamper Protection is on |
| Group Policy "Turn off Defender" | Engine off, but the **WinDefend service** restarts real-time protection |
| All of the above, and it *still* came back | **Windows Update re-enabled Tamper Protection**, undoing everything |

The permanent fix therefore has three pillars:

1. **Kill the `WinDefend` service at the registry level** (needs Safe Mode) so
   there's nothing left to restart protection.
2. **Stop Windows Update** so it can't silently re-arm Tamper Protection.
3. **Snapshot + network isolation** so your known-good "off" state is one click
   away and nothing phones home to re-provision Defender.

---

## Full step-by-step

### Step 1 — Snapshot the clean VM
Before touching anything, take a VM snapshot (VMware: *Snapshot → Take
Snapshot*; VirtualBox: *Machine → Take Snapshot*). This is your undo button.

### Step 2 — Isolate the network and disable Windows Update
1. Set the VM's network adapter to **Host-only** (or NAT with no outbound, or
   simply disconnect the cable in the VM settings).
2. Disable Windows Update so it can't re-enable Tamper Protection:
   - `Win + R` → `services.msc`
   - Find **Windows Update** → double-click → **Startup type: Disabled** → Stop.
   - (The script also sets the `NoAutoUpdate` policy key as a backstop.)

### Step 3 — Turn off Tamper Protection (manual — cannot be scripted)
Microsoft deliberately blocks any programmatic way to do this.
1. Open **Windows Security**
2. **Virus & threat protection** → **Manage settings**
3. Set **Tamper Protection** → **Off**
4. While you're here, also turn **Real-time protection** off (it'll grey back
   later; that's fine, the script finishes the job).

### Step 4 — Boot into Safe Mode
The `WinDefend` service keys are owned by *TrustedInstaller* and protected while
Windows runs normally. Safe Mode is where you can actually disable them.
1. `Win + R` → `msconfig`
2. **Boot** tab → check **Safe boot** (**Minimal**)
3. **OK** → **Restart**

### Step 5 — Run the script as Administrator
1. In Safe Mode: Start → type **PowerShell** → right-click **Run as
   administrator**
2. `cd` to this repo's folder, e.g.:
   ```powershell
   cd C:\Tools\disabledefender
   ```
3. Run it:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Disable-Defender.ps1
   ```
4. Each service should print **`[OK] ... Start=4 (disabled)`**. If you see
   `[!!]`, you're not in Safe Mode or not elevated — fix that and re-run.

### Step 6 — Leave Safe Mode and reboot
1. `msconfig` → **Boot** tab → **uncheck** Safe boot
2. **OK** → **Restart**

### Step 7 — Verify
Open an **Administrator** PowerShell and check:
```powershell
Get-MpComputerStatus | Select RealTimeProtectionEnabled, AntivirusEnabled, AMServiceEnabled
sc query WinDefend
```
Expected:
- `RealTimeProtectionEnabled : False`
- `AntivirusEnabled : False`
- `WinDefend` not running / set to disabled.

### Step 8 — Snapshot the "Defender-off" state
Take a **second snapshot** now labeled e.g. `clean + defender off`. This becomes
your go-to base for every analysis task, so you never fight Defender again.

### Step 9 — Install / use FlareVM
Now run the FlareVM installer (or revert to this snapshot before each task).
Because Defender is gone, the installer won't quarantine tools mid-install.

---

## What the script changes

| Layer | Action |
|-------|--------|
| `Set-MpPreference` | Disables real-time, behavior, script, IOAV, and archive scanning; sets MAPS/sample submission to never |
| Policy keys (`HKLM\SOFTWARE\Policies\Microsoft\Windows Defender`) | `DisableAntiSpyware`, `DisableAntiVirus`, real-time + spynet policy off |
| Scheduled tasks | Disables all `\Microsoft\Windows\Windows Defender\` tasks |
| Services (`Start=4`) | `WinDefend`, `Sense`, `WdNisSvc`, `WdNisDrv`, `WdFilter`, `WdBoot`, `SecurityHealthService` — with automatic registry-ownership grab |
| Windows Update | `NoAutoUpdate=1` so updates can't re-arm Tamper Protection |

---

## Troubleshooting

**"It still came back after a few days."**
Windows Update ran. Confirm the Windows Update service is **Disabled** (Step 2)
and the VM has no internet. That's the #1 cause.

**"The script printed `[!!]` for WinDefend."**
You weren't in Safe Mode, or PowerShell wasn't elevated. Both are required for
the service-disable step. Redo Steps 4–5.

**"Tamper Protection won't turn off / is greyed."**
It can be locked by a management policy or a pending update. Disconnect the
network, reboot, and try the UI again. It must be off *before* the script runs.

**"I need Defender back."**
Restore your Step 1 snapshot. That's the clean way — far simpler than manually
re-enabling every service.

---

## Files
- **`Disable-Defender.ps1`** — the automated script (run in Safe Mode, as Admin).
- **`README.md`** — this guide.
