#!/bin/bash
set -eu

_temp_dir=$(echo "$1" | base64 --decode); shift
_id=$(echo "$1" | base64 --decode); shift
_exit_on_nonzero=$(echo "$1" | base64 --decode); shift
_exit_on_stderr=$(echo "$1" | base64 --decode); shift
_command=$(echo "$1" | base64 --decode); shift
_stdoutfile_name=$(echo "$1" | base64 --decode); shift
_stderrfile_name=$(echo "$1" | base64 --decode); shift
_exitcodefile_name=$(echo "$1" | base64 --decode); shift
_is_delete=$(echo "$1" | base64 --decode); shift

_stderrfile="$_temp_dir/$_stderrfile_name"
_stdoutfile="$_temp_dir/$_stdoutfile_name"
_exitcodefile="$_temp_dir/$_exitcodefile_name"

if [ "$_is_delete" = "true" ]; then
  _cmdfile="$_temp_dir/cmd.$_id.delete.sh"
else
  _cmdfile="$_temp_dir/cmd.$_id.create.sh"
fi

# Write the command to a file to execute from
echo "$_command" > "$_cmdfile"
# Always force the command file to exit with the last exit code
echo 'exit $?' >> "$_cmdfile"

set +e
  2>"$_stderrfile" >"$_stdoutfile" bash "$_cmdfile"
  _exitcode=$?
set -e

# Read the stderr file
_stderr=$(cat "$_stderrfile")

# Delete the files
rm "$_cmdfile"

# If we want to kill Terraform on a non-zero exit code and the exit code was non-zero, OR
# we want to kill Terraform on a non-empty stderr and the stderr was non-empty
if ( [ "$_exit_on_nonzero" = "true" ] && [ $_exitcode -ne 0 ] ) || ( [ "$_exit_on_stderr" = "true" ] && ! [ -z "$_stderr" ] ); then

  # Since we're exiting with an error code, we don't need to read the output files in the Terraform config,
  # and we won't get a chance to delete them via Terraform, so delete them now
  rm "$_stderrfile"
  rm "$_stdoutfile"

  # If there was a stderr, write it out as an error
  if ! [ -z "$_stderr" ]; then
    >&2 echo "$_stderr"
  fi

  # If a non-zero exit code was given, exit with it
  if [ $_exitcode -ne 0 ]; then
      exit $_exitcode
  fi

  # Otherwise, exit with a default non-zero exit code
  exit 1
fi

if [ "$_is_delete" = "true" ]; then
  # If this is a delete command, we don't need the files since we won't be reading them
  # in Terraform, so delete them
  rm "$_stderrfile"
  rm "$_stdoutfile"
else
  # If it's not a delete command, then we want to read the exit code later, so store the exit code in a file
  echo -n $_exitcode >"$_exitcodefile"
fi
