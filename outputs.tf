output "id" {
  description = "A unique ID for this resource. The ID does not change when the shell command is re-run."
  value       = random_uuid.uuid.result
}

output "stdout" {
  description = "The stdout output of the shell command."
  value       = local.outputs.stdout
}

output "stderr" {
  description = "The stderr output of the shell command."
  value       = local.outputs.stderr
}

output "exit_code" {
  description = "The exit status code of the shell command."
  value       = tonumber(local.outputs.exit_code)
}

output "version" {
  description = "The version of the shell resource (see the `track_version` input variable)."
  value       = var.track_version ? module.state_keeper[0].output : null
}
