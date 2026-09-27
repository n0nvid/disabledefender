<#
    Disable-Defender.ps1
    ------------------------------------------------------------------
    Permanently disables Microsoft Defender for an ISOLATED malware-analysis
    VM (FlareVM). NOT for a production or internet-connected machine.

    RUN ORDER (important):
      1. Snapshot the VM first.
      2. Turn OFF Tamper Protection by hand:
           Windows Security > Virus & threat protection > Manage settings
           > Tamper Protection = Off
         (There is no supported way to script this; it must be done in the UI.)
      3. Boot into SAFE MODE:
           msconfig > Boot tab > check "Safe boot" (Minimal) > reboot
      4. Open PowerShell AS ADMINISTRATOR and run this script.
      5. When it finishes, uncheck "Safe boot" in msconfig and reboot normally.

    Running in normal mode will still do most of the work, but the
    service-disable step (the part that makes real-time protection STAY dead)
    will fail with Access Denied unless run from Safe Mode.
    ------------------------------------------------------------------
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "==> Disable-Defender starting..." -ForegroundColor Cyan

# --- 0. Privilege helper: enable SeTakeOwnershipPrivilege / SeRestorePrivilege ---
$def = @'
using System;
using System.Runtime.InteropServices;
public class Priv {
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr h, int acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TOKPRIV1LUID np, int len, IntPtr prev, IntPtr rel);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [StructLayout(LayoutKind.Sequential, Pack=1)]
    struct TOKPRIV1LUID { public int Count; public long Luid; public int Attr; }
    const int SE_PRIVILEGE_ENABLED = 0x2;
    const int TOKEN_ADJUST_PRIVILEGES = 0x20;
    const int TOKEN_QUERY = 0x8;
    public static void Enable(string priv) {
        IntPtr tok; TOKPRIV1LUID tp;
        OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tok);
        tp.Count = 1; tp.Luid = 0; tp.Attr = SE_PRIVILEGE_ENABLED;
        LookupPrivilegeValue(null, priv, out tp.Luid);
        AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
'@
Add-Type $def
[Priv]::Enable("SeTakeOwnershipPrivilege")
[Priv]::Enable("SeRestorePrivilege")

function Take-KeyOwnership($path) {
    # $path like "SYSTEM\CurrentControlSet\Services\WinDefend"
    $admins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $path, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if ($key) {
        $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $acl.SetOwner($admins); $key.SetAccessControl($acl)
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $admins, "FullControl", "ContainerInherit", "None", "Allow")
        $acl2 = $key.GetAccessControl()
        $acl2.SetAccessRule($rule); $key.SetAccessControl($acl2)
        $key.Close()
    }
}

# --- 1. Live protection knobs (works only while Tamper Protection is off) ---
Write-Host "==> Setting MpPreference flags..." -ForegroundColor Cyan
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true
Set-MpPreference -DisableBlockAtFirstSeen $true
Set-MpPreference -DisableIOAVProtection $true
Set-MpPreference -DisableScriptScanning $true
Set-MpPreference -DisableArchiveScanning $true
Set-MpPreference -DisableIntrusionPreventionSystem $true
Set-MpPreference -MAPSReporting Disabled
Set-MpPreference -SubmitSamplesConsent NeverSend

# --- 2. Policy registry keys (survive reboot) ---
Write-Host "==> Writing policy keys..." -ForegroundColor Cyan
$base = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name "DisableAntiSpyware"    -Value 1 -Type DWord
Set-ItemProperty -Path $base -Name "DisableAntiVirus"      -Value 1 -Type DWord
New-Item -Path "$base\Real-Time Protection" -Force | Out-Null
Set-ItemProperty -Path "$base\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
Set-ItemProperty -Path "$base\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord
Set-ItemProperty -Path "$base\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord
New-Item -Path "$base\Spynet" -Force | Out-Null
Set-ItemProperty -Path "$base\Spynet" -Name "SpynetReporting"      -Value 0 -Type DWord
Set-ItemProperty -Path "$base\Spynet" -Name "SubmitSamplesConsent" -Value 2 -Type DWord

# --- 3. Disable scheduled tasks ---
Write-Host "==> Disabling Defender scheduled tasks..." -ForegroundColor Cyan
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\" |
    Disable-ScheduledTask | Out-Null

# --- 4. Disable the services (the part that makes it STICK) ---
Write-Host "==> Disabling Defender services (needs Safe Mode)..." -ForegroundColor Cyan
$svcs = "WinDefend","Sense","WdNisSvc","WdNisDrv","WdFilter","WdBoot","SecurityHealthService"
foreach ($s in $svcs) {
    $p = "SYSTEM\CurrentControlSet\Services\$s"
    Take-KeyOwnership $p
    try {
        Set-ItemProperty -Path "HKLM:\$p" -Name "Start" -Value 4 -Type DWord -ErrorAction Stop
        Write-Host "    [OK]  $s -> Start=4 (disabled)" -ForegroundColor Green
    } catch {
        Write-Host "    [!!]  $s could not be set - are you in Safe Mode as Admin?" -ForegroundColor Yellow
    }
}

# --- 5. Stop Windows Update from re-enabling Defender ---
Write-Host "==> Disabling Windows Update auto-restart of Defender..." -ForegroundColor Cyan
$wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $wu -Force | Out-Null
Set-ItemProperty -Path $wu -Name "NoAutoUpdate" -Value 1 -Type DWord

Write-Host ""
Write-Host "==> Done. Now:" -ForegroundColor Cyan
Write-Host "    1. msconfig > Boot > UNcheck 'Safe boot'"
Write-Host "    2. Reboot."
Write-Host "    3. Verify: Get-MpComputerStatus  (RealTimeProtectionEnabled should be False)"
Write-Host "       and 'sc query WinDefend' should show STOPPED / not start."
