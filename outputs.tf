//==================================================
//     Outputs that match the input variables
//==================================================
output "command_unix" {
  description = "The value of the `command_unix` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.command_unix
}
output "command_windows" {
  description = "The value of the `command_windows` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.command_windows
}
output "command_destroy_unix" {
  description = "The value of the `command_destroy_unix` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.command_destroy_unix
}
output "command_destroy_windows" {
  description = "The value of the `command_destroy_windows` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.command_destroy_windows
}
output "environment" {
  description = "The value of the `environment` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.env_vars
}
output "environment_sensitive" {
  description = "The value of the `environment_sensitive` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.env_vars_sensitive
}
output "environment_triggerless" {
  description = "The value of the `environment_triggerless` input variable, or the default value if the input was `null`, with all carriage returns removed."
  value       = local.env_vars_triggerless
}
output "triggers" {
  description = "The value of the `triggers` input variable, or the default value if the input was `null`."
  value       = local.var_triggers
}
output "working_dir" {
  description = "The value of the `working_dir` input variable."
  value       = local.var_working_dir
}
output "fail_create_on_nonzero_exit_code" {
  description = "The value of the `fail_create_on_nonzero_exit_code` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_nonzero_exit_code
}
output "fail_create_on_stderr" {
  description = "The value of the `fail_create_on_stderr` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_stderr
}
output "fail_create_on_timeout" {
  description = "The value of the `fail_create_on_timeout` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_timeout
}
output "fail_destroy_on_nonzero_exit_code" {
  description = "The value of the `fail_destroy_on_nonzero_exit_code` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_nonzero_exit_code
}
output "fail_destroy_on_stderr" {
  description = "The value of the `fail_destroy_on_stderr` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_stderr
}
output "fail_destroy_on_timeout" {
  description = "The value of the `fail_destroy_on_timeout` input variable, or the default value if the input was `null`."
  value       = local.var_fail_create_on_timeout
}
output "timeout_create" {
  description = "The value of the `timeout_create` input variable, or the default value if the input was `null`."
  value       = local.var_timeout_create
}
output "timeout_destroy" {
  description = "The value of the `timeout_destroy` input variable, or the default value if the input was `null`."
  value       = local.var_timeout_destroy
}
output "suppress_console" {
  description = "The value of the `suppress_console` input variable, or the default value if the input was `null`."
  value       = local.var_suppress_console
}
output "unix_interpreter" {
  description = "The value of the `unix_interpreter` input variable, or the default value if the input was `null`."
  value       = local.var_unix_interpreter
}

//==================================================
//       Outputs generated by this module
//==================================================
output "id" {
  description = "A unique ID for this resource. The ID does not change when the shell command is re-run."
  value       = local.execution_id
}
output "stdout" {
  description = "The stdout output of the shell command, with all carriage returns and trailing newlines removed."
  value       = local.stdout_censored
}
output "stderr" {
  description = "The stderr output of the shell command, with all carriage returns and trailing newlines removed."
  value       = local.stderr_censored
}
output "exit_code" {
  description = "The exit status code of the shell command. If the `timeout` input variable was provided and the command timed out, this will be `null`."
  value       = tonumber(local.outputs.exit_code)
}
