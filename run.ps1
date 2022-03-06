# Equivalent of set -e
$ErrorActionPreference = "Stop"

# Equivalent of set -u (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.1)
set-strictmode -version 3.0
$_temp_dir = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[0]))
$_id = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[1]))
$_exit_on_nonzero = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[2]))
$_exit_on_stderr = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[3]))
$_command = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[4]))
$_stdoutfile_name = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[5]))
$_stderrfile_name = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[6]))
$_exitcodefile_name = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[7]))
$_is_delete = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[8]))

$_stderrfile = "$_temp_dir/$_stderrfile_name"
$_stdoutfile = "$_temp_dir/$_stdoutfile_name"
$_exitcodefile = "$_temp_dir/$_exitcodefile_name"

if ( "$_is_delete" -eq "true" ) {
    $_cmdfile = "$_temp_dir/cmd.$_id.delete.ps1"
}
else {
    $_cmdfile = "$_temp_dir/cmd.$_id.create.ps1"
}

# Write the command to a file
[System.IO.File]::WriteAllText("$_cmdfile", "$_command")

# Always force the command file to exit with the last exit code
[System.IO.File]::AppendAllText("$_cmdfile", "`n`nExit `$LASTEXITCODE")

# Equivalent of set +e
$ErrorActionPreference = "Continue"
$_process = Start-Process powershell.exe -ArgumentList "-file ""$_cmdfile""" -Wait -PassThru -NoNewWindow -RedirectStandardError "$_stderrfile" -RedirectStandardOutput "$_stdoutfile"
$_exitcode = $_process.ExitCode
$ErrorActionPreference = "Stop"

# Read the stderr file
$_stderr = [System.IO.File]::ReadAllText("$_stderrfile")

# Delete the command file
Remove-Item "$_cmdfile"

# If we want to kill Terraform on a non-zero exit code and the exit code was non-zero, OR
# we want to kill Terraform on a non-empty stderr and the stderr was non-empty
if ((( "$_exit_on_nonzero" -eq "true" ) -and $_exitcode) -or (( "$_exit_on_stderr" -eq "true" ) -and "$_stderr")) {
    
    # Since we're exiting with an error code, we don't need to read the output files in the Terraform config,
    # and we won't get a chance to delete them via Terraform, so delete them now
    Remove-Item "$_stderrfile"
    Remove-Item "$_stdoutfile"

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

if ( "$_is_delete" -eq "true" ) {
    Remove-Item "$_stderrfile" -ErrorAction Ignore
    Remove-Item "$_stdoutfile" -ErrorAction Ignore
}
else {
    # Store the exit code in a file
    [System.IO.File]::WriteAllText("$_exitcodefile", "$_exitcode")
}
