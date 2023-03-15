set -e
if ! [ -z "$BASH" ]; then
    # Only Bash supports this feature
    set -o pipefail
fi
# Set this after checking for the BASH variable
set -u

# This checks if we're running on MacOS
_kernel_name="$(uname -s)"
case "${_kernel_name}" in
    darwin*|Darwin*)    
        # It's MacOS.
        # Mac doesn't support the "-d" flag for base64 decoding, 
        # so we have to use the full "--decode" flag instead.
        _decode_flag="--decode"
        # Mac doesn't support the "-w" flag for base64 wrapping, 
        # and it isn't needed because by default it doens't break lines.
        _wrap_flag="" ;;
    *)
        # It's NOT MacOS.
        # Not all Linux base64 installs (e.g. BusyBox) support the full
        # "--decode" flag. So, we use "-d" here, since it's supported
        # by everything except MacOS.
        _decode_flag="-d"
        # All non-Mac installs need this to be specified to prevent line
        # wrapping, which adds newlines that we don't want.
        _wrap_flag="-w0" ;;
esac

# This checks if the "-n" flag is supported on this shell, and sets vars accordingly
if [ "`echo -n`" = "-n" ]; then
  _echo_n=""
  _echo_c="\c"
else
  _echo_n="-n"
  _echo_c=""
fi

# We know that all of the inputs are base64-encoded, and "|" is not a valid base64 character, so therefore it
# cannot possibly be included in the stdin.
_execution_id="$(echo "${1}" | base64 $_decode_flag)"; shift
_directory="$(echo "${1}" | base64 $_decode_flag)"; shift
_environment_file_name="$(echo "${1}" | base64 $_decode_flag)"; shift
_timeout="$(echo "${1}" | base64 $_decode_flag)"; shift
_exit_on_nonzero="$(echo "${1}" | base64 $_decode_flag)"; shift
_exit_on_stderr="$(echo "${1}" | base64 $_decode_flag)"; shift
_exit_on_timeout="$(echo "${1}" | base64 $_decode_flag)"; shift
_debug="$(echo "${1}" | base64 $_decode_flag)"; shift
_command_b64="${1}"; shift
_is_create="$(echo "${1}" | base64 $_decode_flag)"; shift
_stdoutfile_name="$(echo "${1}" | base64 $_decode_flag)"; shift
_stderrfile_name="$(echo "${1}" | base64 $_decode_flag)"; shift
_exitcodefile_name="$(echo "${1}" | base64 $_decode_flag)"; shift
_shell="$(echo "${1}" | base64 $_decode_flag)"; shift

# The filenames to direct output to
_stderrfile="$_directory/$_stderrfile_name"
_stdoutfile="$_directory/$_stdoutfile_name"
_exitcodefile="$_directory/$_exitcodefile_name"
_debugfile="$_directory/$_execution_id.debug"
_environment_file="$_directory/$_environment_file_name"

_environment="$(cat $_environment_file)"

# Remove any existing output files with the same UUID
rm -f "$_stderrfile"
rm -f "$_stdoutfile"
rm -f "$_exitcodefile"
rm -f "$_debugfile"

# Delete the environment file, unless we're in debug mode
if [ $_debug != "true" ] ; then
    rm -f "$_environment_file"
fi

if [ $_debug = "true" ] ; then echo "Arguments loaded" > "$_debugfile"; fi

# Split the env var input on semicolons. We use semicolons because we know
# that neither the base64-encoded name or value will contain a semicolon.
IFS=";"
set -o noglob
set -- $_environment""
for _env in "$@"; do
    if [ -z "$_env" ] ; then
        continue
    fi
    # For each env var, split it on a colon. We use colons because we know
    # that neither the env var name nor the base64-encoded value will contain
    # a colon.
    _key="$(echo $_echo_n "${_env}${_echo_c}" | cut -d':' -f1 | base64 $_decode_flag)"
    _val="$(echo $_echo_n "${_env}${_echo_c}" | cut -d':' -f2 | base64 $_decode_flag)"
    export "$_key"="$_val"
done

# A command to run at the very end of the input script. This forces the script to
# always exit with the exit code of the last command that returned an exit code.
_cmd_suffix=<<EOF
exit $?
EOF

# This is a custom function that executes the command, but interrupts it with a SIGALARM
# if it runs for too long. Not all operating systems have "timeout" built in, so
# we need to have a custom function that simulates it.
perl_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# Run the command, but don't exit this script on an error
_timed_out="false"
if [ $_timeout -eq 0 ] ; then
    # No timeout is set, so run the command without a timeout
    if [ $_debug = "true" ] ; then echo "Starting process with no timeout" >> "$_debugfile"; fi
    set +e
    2>"$_stderrfile" >"$_stdoutfile" $_shell -c "$(echo "${_command_b64}" | base64 $_decode_flag)${_cmd_suffix}"
    _exitcode=$?
    set -e
else
    # Add a prefix to the command, which wraps the commands in a block
    _cmd_prefix=<<EOF
{
EOF
    # Extend the suffix after the command, which redirects all stderr to a new descriptor
    # We do this so that when timeout alarm signals cause the shell to print the signal
    # description, it doesn't get captured into the stderr that we actually want.
    _cmd_suffix=<<EOF
$_cmd_suffix
} 2>&3
EOF
    # Default to using the built-in timeout command
    _timeout_cmd="timeout"
    if ! command -v $_timeout_cmd >/dev/null 2>/dev/null; then
        # If it doesn't exist though, use the custom Perl one we created
        _timeout_cmd="perl_timeout"
    fi

    # There is a timeout set, so run the command with it
    if [ $_debug = "true" ] ; then echo "Starting process with a $_timeout second timeout" >> "$_debugfile"; fi
    set +e
    $_timeout_cmd $_timeout 3>"$_stderrfile" >"$_stdoutfile" $_shell -c "${_cmd_prefix}$(echo "${_command_b64}" | base64 $_decode_flag)${_cmd_suffix}"
    _exitcode=$?
    set -e
    # Check if it timed out. 142 is the exit code from a Perl alarm signal, 124 is the exit code from most built-in 
    # "timeout" commands, and 143 is the exit code from the Busybox "timeout" command.
    if [ $_exitcode -eq 142 ] || [ $_exitcode -eq 124 ] || [ $_exitcode -eq 143 ] ; then
        if [ $_debug = "true" ] ; then echo "Process timed out after $_timeout seconds" >> "$_debugfile"; fi
        _timed_out="true"
    fi
fi

# Write the exit code to a file
if [ $_is_create = "true" ]; then echo $_echo_n "${_exitcode}${_echo_c}" > $_exitcodefile; fi

if [ $_debug = "true" ] ; then echo "Execution complete" >> "$_debugfile"; fi

# Read the stderr and stdout files
if [ $_debug = "true" ] ; then echo "Reading stdout file" >> "$_debugfile"; fi
_stdout="$(cat "$_stdoutfile")"
if [ $_debug = "true" ] ; then echo "Reading stderr file" >> "$_debugfile"; fi
_stderr="$(cat "$_stderrfile")"
if [ $_debug = "true" ] ; then echo "Finished reading output files" >> "$_debugfile"; fi

# Check if the execution timed out
if [ "$_timed_out" = "true" ] ; then
    if [ "$_exit_on_timeout" = "true" ] ; then
        if [ $_debug = "true" ] ; then echo "Failing due to a timeout error" >> "$_debugfile"; fi
        >&2 echo $_echo_n "Execution timed out after $_timeout seconds${_echo_c}"
        exit 1
    else
        _exitcode="null"
    fi
fi

# If we want to kill Terraform on a non-zero exit code and the exit code was non-zero, OR
# we want to kill Terraform on a non-empty stderr and the stderr was non-empty
if ( [ "$_exit_on_nonzero" = "true" ] && [ "$_exitcode" != "null" ] && [ $_exitcode -ne 0 ] ) || ( [ "$_exit_on_stderr" = "true" ] && ! [ -z "$_stderr" ] ); then
    # If there was a stderr, write it out as an error
    if ! [ -z "$_stderr" ] ; then
        if [ $_debug = "true" ] && [ "$_exit_on_stderr" = "true" ] ; then echo "Failing due to presence of stderr output" >> "$_debugfile"; fi
        >&2 echo $_echo_n "${_stderr}${_echo_c}"
    fi

    # If a non-zero exit code was given, exit with it
    if ( [ "$_exitcode" != "null" ] && [ "$_exitcode" -ne 0 ] ); then
        if [ $_debug = "true" ] && [ "$_exit_on_nonzero" = "true" ] ; then echo "Failing due to a non-zero exit code ($_exitcode)" >> "$_debugfile"; fi
        exit $_exitcode
    fi
    if [ $_debug = "true" ] ; then echo -e "\nStdout:\n$_stdout" >> "$_debugfile"; fi
    if [ $_debug = "true" ] ; then echo -e "\nStderr:\n$_stderr" >> "$_debugfile"; fi

    # Otherwise, exit with a default non-zero exit code
    exit 1
fi

# If it's a destroy provisioner, remove the files because they can't be read anyways
if [ $_is_create != "true" ]; then
    rm -f "$_stderrfile"
    rm -f "$_stdoutfile"
    rm -f "$_exitcodefile"
fi

if [ $_debug = "true" ] ; then echo "Done!" >> "$_debugfile"; fi
exit 0
