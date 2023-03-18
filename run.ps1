# Equivalent of set -e
$ErrorActionPreference = "Stop"

# Equivalent of set -u (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.1)
set-strictmode -version 3.0

$_inputs = $args[0].Trim("`"").Split("|")

$_uses_input_files = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[0])))
$_is_create = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[1])))
$_environment_input = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[2]))
$_command_input = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[3]))
$_timeout = [System.Convert]::ToInt32([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[4])))
$_exit_on_nonzero = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[5])))
$_exit_on_stderr = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[6])))
$_exit_on_timeout = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[7])))
$_execution_id = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[8]))
$_directory = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[9]))
$_debug = [System.Convert]::ToBoolean([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[10])))
$_stdout_file = "$_directory/" + [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[11]))
$_stderr_file = "$_directory/" + [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[12]))
$_exitcode_file = "$_directory/" + [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_inputs[13]))

if ($_is_create) {
    $_debugfile = "$_directory/$_execution_id.create.debug.txt"
}
else {
    $_debugfile = "$_directory/$_execution_id.delete.debug.txt"
}

if ($_uses_input_files) {
    $_cmdfile = "$_directory/$_command_input"
    $_envfile = "$_directory/$_environment_input"
    $_environment = [System.IO.File]::ReadAllText("$_envfile")
    # Delete the environment input file immediately after reading it
    # unless we're using debug mode, in which case we might want to 
    # review it for debugging purposes.
    if ( -not $_debug ) {
        Remove-Item -Path "$_envfile"
    }
}
else {
    if ($_is_create) {
        $_cmdfile = "$_directory/$_execution_id.create.ps1"
    }
    else {
        $_cmdfile = "$_directory/$_execution_id.delete.ps1"
    }
    [System.IO.File]::WriteAllText("$_cmdfile", "$_command_input")
    $_environment = $_environment_input
}

# Remove any existing output files with the same UUID
if (Test-Path -Path "$_stdout_file") {
    Remove-Item -Path "$_stdout_file"
}
if (Test-Path -Path "$_stderr_file") {
    Remove-Item -Path "$_stderr_file"
}
if (Test-Path -Path "$_exitcode_file") {
    Remove-Item -Path "$_exitcode_file"
}
# Remove any existing output files with the same UUID
if (Test-Path -Path "$_debugfile") {
    Remove-Item -Path "$_debugfile"
}


####################################################################
# Everything from here to the next marker should be identical 
# to the InvictonLabs/shell-data/external module's PowerShell script
####################################################################

if ($_debug) { Write-Output "Arguments loaded" | Out-File -FilePath "$_debugfile" }

# Set the environment variables
$_env_vars = $_environment.Split(";")
foreach ($_env in $_env_vars) {
    if ( "$_env" -eq "" ) {
        continue
    }
    $_env_parts = $_env.Split(":")
    [Environment]::SetEnvironmentVariable([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_env_parts[0])), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_env_parts[1])), "Process") 
}

if ($_debug) { Write-Output "Environment variables set" | Out-File -FilePath "$_debugfile" }

# Write the command to a file
# Always force the command file to exit with the last exit code
[System.IO.File]::AppendAllText("$_cmdfile", "`nExit `$LASTEXITCODE")

if ($_debug) { Write-Output "Command file prepared" | Out-File -Append -FilePath "$_debugfile" }

# This is a function that recursively kills all child processes of a process
function TreeKill([int]$ProcessId) {
    if ($_debug) { Write-Output "Getting process children for $ProcessId" | Out-File -Append -FilePath "$_debugfile" }
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ProcessId } | ForEach-Object { TreeKill -ProcessId $_.ProcessId }
    if ($_debug) { Write-Output "Killing process $ProcessId" | Out-File -Append -FilePath "$_debugfile" }
    $_p = Get-Process -ErrorAction SilentlyContinue -Id $ProcessId
    if ($_p) {
        Stop-Process -Force -Id $ProcessId
        $_p.WaitForExit(10000) | Out-Null
        if (!$_p.HasExited) {
            $_err = "Failed to kill the process after waiting for $_delay seconds:`n$_"
            if ($_debug) { Write-Output "$_err" | Out-File -Append -FilePath "$_debugfile" }
            Write-Error "$_err"
            Exit -1
        }
    }
}

$_pinfo = New-Object System.Diagnostics.ProcessStartInfo
$_pinfo.FileName = "powershell.exe"
# This allows capturing the output to a variable
$_pinfo.RedirectStandardError = $true
$_pinfo.RedirectStandardOutput = $true
$_pinfo.UseShellExecute = $false
$_pinfo.CreateNoWindow = $false
$_pinfo.Arguments = "-NoProfile -File `"$_cmdfile`""
$_process = New-Object System.Diagnostics.Process
$_process.StartInfo = $_pinfo

if ($_debug) { Write-Output "Starting process" | Out-File -Append -FilePath "$_debugfile" }

$ErrorActionPreference = "Continue"
$_process.Start() | Out-Null
$_out_task = $_process.StandardOutput.ReadToEndAsync();
$_err_task = $_process.StandardError.ReadToEndAsync();
$_timed_out = $false

if ([int]$_timeout -eq 0) {
    $_process.WaitForExit() | Out-Null
}
else {
    $_process_result = $_process.WaitForExit($_timeout * 1000)
    if (-Not $_process_result) {
        if ($_debug) { Write-Output "Process timed out, killing..." | Out-File -Append -FilePath "$_debugfile" }
        TreeKill -ProcessId $_process.Id
        $_timed_out = $true
    }
}
$ErrorActionPreference = "Stop"

if ($_debug) { Write-Output "Finished process" | Out-File -Append -FilePath "$_debugfile" }

$_stdout = $_out_task.Result
$_stderr = $_err_task.Result
$_exitcode = $_process.ExitCode

# Delete the command file, unless we're using debug mode,
# in which case we might want to review it for debugging
# purposes.
if ( -not $_debug ) {
    Remove-Item -Path "$_cmdfile"
}

# Check if the execution timed out
if ($_timed_out) {
    # If it did, check if we're supposed to exit the script on a timeout
    if ( $_exit_on_timeout ) {
        $ErrorActionPreference = "Continue"
        Write-Error "Execution timed out after $_timeout seconds"
        $ErrorActionPreference = "Stop"
        Exit -1
    }
    else {
        $_exitcode = "null"
    }
}

# If we want to kill Terraform on a non-zero exit code and the exit code was non-zero, OR
# we want to kill Terraform on a non-empty stderr and the stderr was non-empty
if ((( $_exit_on_nonzero ) -and ($_exitcode -ne 0) -and ($_exitcode -ne "null")) -or (( $_exit_on_stderr ) -and "$_stderr")) {
    # If there was a stderr, write it out as an error
    if ("$_stderr") {
        # Set continue to not kill the process on writing an error, so we can exit with the desired exit code
        $ErrorActionPreference = "Continue"
        Write-Error "$_stderr"
        $ErrorActionPreference = "Stop"
    }
    # If a non-zero exit code was given, exit with it
    if (($_exitcode -ne 0) -and ($_exitcode -ne "null")) {
        exit $_exitcode
    }
    # Otherwise, exit with a default non-zero exit code
    exit 1
}


#############################################
# Outputs are different for data and resource
#############################################

# Only write output files if it's a create (not a destroy)
if ($_is_create) {
    if ($_debug) { Write-Output "Creating output files" | Out-File -Append -FilePath "$_debugfile" }
    [System.IO.File]::WriteAllText("$_stdout_file", "$_stdout")
    [System.IO.File]::WriteAllText("$_stderr_file", "$_stderr")
    [System.IO.File]::WriteAllText("$_exitcode_file", "$_exitcode")
}

if ($_debug) { Write-Output "Done!" | Out-File -Append -FilePath "$_debugfile" }
Exit 0