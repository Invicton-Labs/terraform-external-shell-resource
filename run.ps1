# Equivalent of set -e
$ErrorActionPreference = "Stop"

# Equivalent of set -u (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.1)
set-strictmode -version 3.0
$_path = $args[0]
$_id = $args[1]
$_failonerr = $args[2]
$_cmd = $args[3]
$_stderrfile = "$_path/stderr.$_id"
$_stdoutfile = "$_path/stdout.$_id"
$_exitcodefile = "$_path/exitstatus.$_id"
$_cmdfile = "$_path/cmd.$_id.ps1"

# Write the command to a file to execute from
# First start with a command that causes the script to exit if an error is thrown
Write-Output '$ErrorActionPreference = "Stop"' | Out-File -FilePath "$_cmdfile"
# Now write the command itself 
Write-Output "$_cmd" | Out-File -Append -FilePath "$_cmdfile"

# Equivalent of set +e
$ErrorActionPreference = "Continue"
$_process = Start-Process powershell.exe -ArgumentList "-file ""$_cmdfile""" -Wait -PassThru -NoNewWindow -RedirectStandardError "$_stderrfile" -RedirectStandardOutput "$_stdoutfile"
$_exitcode = $_process.ExitCode
$ErrorActionPreference = "Stop"

# Delete the command file
Remove-Item "$_cmdfile"

[System.IO.File]::WriteAllText("$_exitcodefile", "$_exitcode", [System.Text.Encoding]::ASCII)

if (( "$_failonerr" -eq "true" ) -and $_exitcode) {
    # If it should fail on an error, and it did fail, read the stderr file
    # Exit with the error message and code
    $_stderr = [System.IO.File]::ReadAllText("$_stderrfile")
    Write-Error "$_stderr"
    exit $_exitcode
}
