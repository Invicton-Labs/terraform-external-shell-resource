# Equivalent of set -e
$ErrorActionPreference = "Stop"

# Equivalent of set -u (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.1)
set-strictmode -version 3.0
$_temp_dir = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[0]))
$_id = $args[1]
$_exit_on_nonzero = [System.Convert]::ToBoolean($args[2])
$_exit_on_stderr = [System.Convert]::ToBoolean($args[3])
$_exit_on_timeout = [System.Convert]::ToBoolean($args[4])
$_command = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[5]))
$_stdoutfile_name = $args[6]
$_stderrfile_name = $args[7]
$_exitcodefile_name = $args[8]
$_timeout = $args[9]
$_is_delete = [System.Convert]::ToBoolean($args[10])
$_debug = [System.Convert]::ToBoolean($args[11])

# Determine the temporary file names to use
$_stdoutfile = "$_temp_dir/$_stdoutfile_name"
$_stderrfile = "$_temp_dir/$_stderrfile_name"
$_exitcodefile = "$_temp_dir/$_exitcodefile_name"
if ($_is_delete) {
    $_cmdfile = "$_temp_dir/$_id.delete.ps1"
    $_debugfile = "$_temp_dir/$_id.delete.debug"
}
else {
    $_cmdfile = "$_temp_dir/$_id.create.ps1"
    $_debugfile = "$_temp_dir/$_id.create.debug"
}

if ($_debug) { Write-Output "Arguments loaded" | Out-File -FilePath "$_debugfile" }

# Remove any existing output files with the same UUID
if (Test-Path -Path "$_stdoutfile") {
    Remove-Item -Path "$_stdoutfile"
}
if (Test-Path -Path "$_stderrfile") {
    Remove-Item -Path "$_stderrfile"
}
if (Test-Path -Path "$_exitcodefile") {
    Remove-Item -Path "$_exitcodefile"
}

# Write the command to a file
[System.IO.File]::WriteAllText("$_cmdfile", "$_command")

# Always force the command file to exit with the last exit code
[System.IO.File]::AppendAllText("$_cmdfile", "`n`nExit `$LASTEXITCODE")

if ($_debug) { Write-Output "Command file prepared" | Out-File -Append -FilePath "$_debugfile" }

function TreeKill([int]$ProcessId) {
    if ($_debug) { Write-Output "Getting process children for $ProcessId" | Out-File -Append -FilePath "$_debugfile" }
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ProcessId } | ForEach-Object { TreeKill -ProcessId $_.ProcessId }
    if ($_debug) { Write-Output "Killing process $ProcessId" | Out-File -Append -FilePath "$_debugfile" }
    $_p = Get-Process -ErrorAction SilentlyContinue -Id $ProcessId
    if ($_p) {
        Stop-Process -Force -Id $ProcessId
        $_p.WaitForExit(10000)
        if (!$_p.HasExited) {
            $_err = "Failed to read stdout file after waiting for $_delay seconds:`n$_"
            if ($_debug) { Write-Output "$_err" | Out-File -Append -FilePath "$_debugfile" }
            Write-Error "$_err"
            Exit -1
        }
    }
}

# Start the process
$_timeout_error = $null
if ($_debug) { Write-Output "Starting process" | Out-File -Append -FilePath "$_debugfile" }
$_process = Start-Process powershell.exe -ArgumentList "-file ""$_cmdfile""" -PassThru -NoNewWindow -RedirectStandardError "$_stderrfile" -RedirectStandardOutput "$_stdoutfile"

if ( $_timeout -eq "0" ) {
    # If there's no timeout set, just wait it out indefinitely
    if ($_debug) { Write-Output "Waiting for process to complete with no timeout" | Out-File -Append -FilePath "$_debugfile" }
    $_process | Wait-Process -ErrorAction SilentlyContinue
    # Capture the exit code when it's done
    $_exitcode = $_process.ExitCode
}
else {
    # If there is a timeout set, wait for the specified number of seconds
    if ($_debug) { Write-Output "Waiting for process to complete with $_timeout second timeout" | Out-File -Append -FilePath "$_debugfile" }
    $_process | Wait-Process -Timeout $_timeout -ErrorAction SilentlyContinue -ErrorVariable _timeout_error
    # Check if it timed out
    if ($_timeout_error) {
        # If it did, kill the process
        if ($_debug) { Write-Output "Process timed out, killing..." | Out-File -Append -FilePath "$_debugfile" }
        TreeKill -ProcessId $_process.Id
        
        # Once the process is killed, set the error code to -1 if we're supposed to exit on a timeout
        if ($_debug) { Write-Output "Successfully killed process" | Out-File -Append -FilePath "$_debugfile" }
        $_exitcode = if ($_exit_on_timeout) { -1 } else { 0 }
    }
    else {
        # It didn't time out, so capture the exit code
        $_exitcode = $_process.ExitCode
    }
}
if ($_debug) { Write-Output "Execution complete" | Out-File -Append -FilePath "$_debugfile" }

function ReadFileAfterUnlock([string]$Filename, [int]$IntervalMilli, [int]$WaitCycles) {
    $_contents = $null
    $i = 0
    while ($true) {
        $_delay = $i * $IntervalMilli / 1000
        try {
            $_contents = [System.IO.File]::ReadAllText("$Filename")
            break
        }
        catch {
            if ($i -lt $WaitCycles) {
                Start-Sleep -Milliseconds $IntervalMilli
                $i = $i + 1
                continue
            }
            if ($_debug) { Write-Output "Failed to read $Filename after $i attempts" | Out-File -Append -FilePath "$_debugfile" }
            Write-Error "Failed to read stdout file after waiting for $_delay seconds:`n$_"
            Exit -1
        }
    }
    $_contents
}

if ($_debug) { Write-Output "Reading stdout file" | Out-File -Append -FilePath "$_debugfile" }
$_stdout = ReadFileAfterUnlock -Filename "$_stdoutfile" -IntervalMilli 100 -WaitCycles 300
if ($_debug) { Write-Output "Reading stderr file" | Out-File -Append -FilePath "$_debugfile" }
$_stderr = ReadFileAfterUnlock -Filename "$_stderrfile" -IntervalMilli 100 -WaitCycles 300
if ($_debug) { Write-Output "Finished reading output files" | Out-File -Append -FilePath "$_debugfile" }

# If the error was due to a timeout, prepend the stderr with that message
if ($_timeout_error) {
    $_stderr = "TIMEOUT after $_timeout seconds.`n" + $_stderr
}

# Delete the command file
if ($_debug) { Write-Output "Deleting command file" | Out-File -Append -FilePath "$_debugfile" }
Remove-Item "$_cmdfile"
if ($_debug) { Write-Output "Command file deleted" | Out-File -Append -FilePath "$_debugfile" }

$_die = $false
if ($_exit_on_timeout -and $_timeout_error ) {
    $_die = $true
    if ($_debug) { Write-Output "Failing due to a timeout error" | Out-File -Append -FilePath "$_debugfile" }
}
elseif ($_exit_on_nonzero -and $_exitcode) {
    $_die = $true
    if ($_debug) { Write-Output "Failing due to a non-zero exit code ($_exitcode)" | Out-File -Append -FilePath "$_debugfile" }
}
elseif ($_exit_on_stderr -and "$_stderr") {
    $_die = $true
    if ($_debug) { Write-Output "Failing due to presence of stderr output" | Out-File -Append -FilePath "$_debugfile" }
}

if ($_die) {
    if ($_debug) { Write-Output "Deleting stdout and stderr files" | Out-File -Append -FilePath "$_debugfile" }
    Remove-Item "$_stdoutfile"
    Remove-Item "$_stderrfile"

    if ($_debug) { Write-Output "`nStdout:`n$_stdout" | Out-File -Append -FilePath "$_debugfile" }
    if ($_debug) { Write-Output "`nStderr:`n$_stderr" | Out-File -Append -FilePath "$_debugfile" }
    # If there was a stderr, write it out as an error
    if ("$_stderr") {
        # Set continue to not kill the process on writing an error, so we can exit with the desired exit code
        $ErrorActionPreference = "Continue"
        Write-Error "$_stderr"
        $ErrorActionPreference = "Stop"
    }
    
    # If a non-zero exit code was given, exit with it
    if ($_exitcode) {
        exit $_exitcode
    }
    
    # Otherwise, exit with a default non-zero exit code
    exit 1
}

# If it's not a delete (it's a create), write the stdout/stderr/exitcode out to file for Terraform to read
if (!$_is_delete) {
    if ($_debug) { Write-Output "Creating output files" | Out-File -Append -FilePath "$_debugfile" }
    [System.IO.File]::WriteAllText("$_stderrfile", "$_stderr")
    [System.IO.File]::WriteAllText("$_exitcodefile", "$_exitcode")
}
if ($_debug) { Write-Output "Done!" | Out-File -Append -FilePath "$_debugfile" }
Exit 0
