output "id" {
  description = "A unique ID for this resource. The ID does not change when the shell command is re-run."
  value = random_uuid.uuid.result
}

output "stdout" {
  description = "The stdout output of the shell command."
  value = local.outputs.stdout
}

output "stderr" {
  description = "The stderr output of the shell command."
  value = local.outputs.stderr
}

output "exitstatus" {
  description = "The exit status code of the shell command."
  value = tonumber(local.outputs.exitstatus)
}
