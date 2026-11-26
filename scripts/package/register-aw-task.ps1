# Registers a per-user scheduled task that starts Malachi ActivityWatch at logon
# and re-checks every 5 minutes. aw-qt holds a lock, so an extra start while it
# is already running exits at once. A real Windows service cannot be used: it has
# no access to the user's desktop, which the window and input watchers need.
param([Parameter(Mandatory = $true)][string]$ExePath)

$ErrorActionPreference = 'Stop'
$taskName = 'Malachi ActivityWatch'
$user = "$env:USERDOMAIN\$env:USERNAME"
$log = Join-Path $env:TEMP 'aw-task-register.log'

$action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory (Split-Path $ExePath)
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $repeat) `
        -Settings $settings -Principal $principal -Force | Out-Null
    "$(Get-Date -Format s) registered with logon + 5 min trigger for $user" | Out-File $log -Append
} catch {
    "$(Get-Date -Format s) logon trigger failed: $_ ; retrying with the 5 min trigger only" | Out-File $log -Append
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $repeat `
        -Settings $settings -Principal $principal -Force | Out-Null
    "$(Get-Date -Format s) registered with 5 min trigger only for $user" | Out-File $log -Append
}
