#!/bin/bash
set -eu

function tobool() {
  if [ $1 -eq 0 ]; then
    echo false
  elif [ $1 -eq 1 ]; then
    echo true
  else
    echo "Unknown boolean value \"$1\"" 1>&2; exit 1
  fi
}

# Account for platform differences in base64 command
# Taken from @nknapp contribution to traefik: traefik/traefik#2344
case "$(uname)" in
  'Linux')
    # On Linux, -d should always work. --decode does not work with Alpine's busybox-binary
    CMD_DECODE_BASE64="base64 -d"
    ;;
  *)
    # Max OS-X supports --decode and -D, but --decode may be supported by other platforms as well.
    CMD_DECODE_BASE64="base64 --decode"
    ;;
esac

_temp_dir=$(echo "$1" | ${CMD_DECODE_BASE64}); shift
_id="$1"; shift
_exit_on_nonzero="$(tobool "$1")"; shift
_exit_on_stderr="$(tobool "$1")"; shift
_exit_on_timeout="$(tobool "$1")"; shift
_command=$(echo "$1" | ${CMD_DECODE_BASE64}); shift
_stdoutfile_name="$1"; shift
_stderrfile_name="$1"; shift
_exitcodefile_name="$1"; shift
_timeout="$1"; shift
_is_delete="$(tobool "$1")"; shift
_debug="$(tobool "$1")"; shift

_stderrfile="$_temp_dir/$_stderrfile_name"
_stdoutfile="$_temp_dir/$_stdoutfile_name"
_exitcodefile="$_temp_dir/$_exitcodefile_name"

if $_is_delete ; then
  _cmdfile="$_temp_dir/cmd.$_id.delete.sh"
  _debugfile="$_temp_dir/$_id.delete.debug"
else
  _cmdfile="$_temp_dir/cmd.$_id.create.sh"
  _debugfile="$_temp_dir/$_id.create.debug"
fi

if $_debug ; then echo "Arguments loaded" > "$_debugfile"; fi

# Remove any existing output files with the same UUID
rm -f "$_stderrfile"
rm -f "$_stdoutfile"
rm -f "$_exitcodefile"

# Write the command to a file to execute from
echo "$_command" > "$_cmdfile"

# Always force the command file to exit with the last exit code
echo 'exit $?' >> "$_cmdfile"

if $_debug ; then echo "Command file prepared" >> "$_debugfile"; fi

_timed_out=false
set +e
  if [ $_timeout == 0 ]; then
    if $_debug ; then echo "Starting process with no timeout" >> "$_debugfile"; fi
    2>"$_stderrfile" >"$_stdoutfile" bash "$_cmdfile"
    _exitcode=$?
  else
    if $_debug ; then echo "Starting process $_timeout second timeout" >> "$_debugfile"; fi
    timeout --kill-after=10 $_timeout 2>"$_stderrfile" >"$_stdoutfile" bash "$_cmdfile"
    _exitcode=$?
    # Check if it timed out
    if [ $_exitcode == 124 ]; then
      if $_debug ; then echo "Process timed out after $_timeout seconds" >> "$_debugfile"; fi
      _timed_out=true
      if $_exit_on_timeout ; then
       # Once the process is killed, set the error code to -1 if we're supposed to exit on a timeout
        _exitcode=-1
      else
        # Otherwise, set the exit code to 0 since timing out shouldn't kill our script
        _exitcode=0
      fi
    fi
  fi
set -e
if $_debug ; then echo "Execution complete" >> "$_debugfile"; fi

# Read the stderr file
if $_debug ; then echo "Reading stdout file" >> "$_debugfile"; fi
_stdout=$(cat "$_stdoutfile")
if $_debug ; then echo "Reading stderr file" >> "$_debugfile"; fi
_stderr=$(cat "$_stderrfile")
if $_debug ; then echo "Finished reading output files" >> "$_debugfile"; fi

# If the error was due to a timeout, prepend the stderr with that message
if $_timed_out ; then
  _stderr="TIMEOUT after $_timeout seconds.
$_stderr"
fi

# Delete the command file
rm "$_cmdfile"

_die=false
if $_exit_on_timeout && $_timed_out ; then
  _die=true
  if $_debug ; then echo "Failing due to a timeout error" >> "$_debugfile"; fi
elif $_exit_on_nonzero && [ $_exitcode != 0 ] ; then
  _die=true
  if $_debug ; then echo "Failing due to a non-zero exit code ($_exitcode)" >> "$_debugfile"; fi
elif $_exit_on_stderr && ! [ -z "$_stderr" ]; then
  _die=true
  if $_debug ; then echo "Failing due to presence of stderr output" >> "$_debugfile"; fi
fi

if $_die ; then
  if $_debug ; then echo "Deleting stdout and stderr files" >> "$_debugfile"; fi
  rm "$_stdoutfile"
  rm "$_stderrfile"

  # Add the stdout and stderr to the debug file for debugging
  if $_debug ; then echo -e "\nStdout:\n$_stdout" >> "$_debugfile"; fi
  if $_debug ; then echo -e "\nStderr:\n$_stderr" >> "$_debugfile"; fi
  
  # If there was a stderr, write it out as an error
  if ! [ -z "$_stderr" ]; then
    >&2 echo -e "\n\n$_stderr"
  fi

  # If a non-zero exit code was given, exit with it
  if [ $_exitcode != 0 ] ; then
      exit $_exitcode
  fi

  # Otherwise, exit with a default non-zero exit code
  exit 1
fi

if ! $_is_delete ; then
  if $_debug ; then echo "Creating output files" >> "$_debugfile"; fi
  echo -e "$_stderr" > "$_stderrfile"
  echo "$_exitcode" > "$_exitcodefile"
fi

if $_debug ; then echo "Done!" >> "$_debugfile"; fi
exit 0
