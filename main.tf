// This is a UUID that represents a single instance of this module
resource "random_uuid" "uuid" {}

locals {
  is_windows = dirname("/") == "\\"
  # These are commands that have no effect
  null_command_unix    = ":"
  null_command_windows = "% ':'"

  command_unix                 = chomp(var.command_unix != null ? var.command_unix : (var.command_windows != null ? var.command_windows : local.null_command_unix))
  command_windows              = chomp(var.command_windows != null ? var.command_windows : (var.command_unix != null ? var.command_unix : local.null_command_windows))
  command_when_destroy_unix    = chomp(var.command_when_destroy_unix != null ? var.command_when_destroy_unix : (var.command_when_destroy_windows != null ? var.command_when_destroy_windows : local.null_command_unix))
  command_when_destroy_windows = chomp(var.command_when_destroy_windows != null ? var.command_when_destroy_windows : (var.command_when_destroy_unix != null ? var.command_when_destroy_unix : local.null_command_windows))

  // The input trigger can be a simple string or a JSON-encoded object
  input_triggers = try(tostring(var.triggers), jsonencode(var.triggers))

  // These are all of the things that, if they change, trigger a re-create
  all_triggers = {
    // If the triggers change, that obviously triggers a re-create
    triggers                     = local.input_triggers
    // If any of the commands change
    command_unix                 = local.command_unix
    command_windows              = local.command_windows
    command_when_destroy_unix    = local.command_when_destroy_unix
    command_when_destroy_windows = local.command_when_destroy_windows

    // If the environment variables change
    environment                  = jsonencode(var.environment)
    sensitive_environment        = sensitive(jsonencode(var.sensitive_environment))

    // If the working directory changes
    working_dir                  = var.working_dir


    // If we want to handle errors differently, that needs a re-create
    fail_on_nonzero_exit_code    = var.fail_on_nonzero_exit_code
    fail_on_stderr               = var.fail_on_stderr

    // These should never change unless the module itself is destroyed/tainted, but we need
    // them in the trigger so that they can be referenced with the "self" variable
    // in the provisioners
    uuid                         = random_uuid.uuid.result
    stdout_file                  = "stdout.${random_uuid.uuid.result}"
    stderr_file                  = "stderr.${random_uuid.uuid.result}"
    exit_code_file               = "exitcode.${random_uuid.uuid.result}"
  }

  // We use <> in the separator because we know jsonencode replaces these characters,
  // so they can never appear in the encoded output
  output_separator = "__3cd07539f7504be6968f30413306d08b_<>_TF_MAGIC_RANDOM_SEP"
}

module "state_keeper" {
  source              = "Invicton-Labs/state-keeper/null"
  version             = "~> 0.1.2"
  count               = var.track_version ? 1 : 0
  read_existing_value = true
  input               = module.state_keeper[0].existing_value == null ? 0 : module.state_keeper[0].existing_value + 1
  triggers            = local.all_triggers
}

resource "null_resource" "shell" {
  triggers = sensitive(local.all_triggers)

  // This provisioner runs the main command
  provisioner "local-exec" {
    when = create
    command = join(" ", concat(dirname("/") == "\\" ? [
      "powershell.exe",
      "${abspath(path.module)}/run.ps1"
      ] : [
      "bash",
      "${abspath(path.module)}/run.sh"
      ], [
      base64encode(abspath("${path.module}/tmpfiles")),
      base64encode(self.triggers.uuid),
      base64encode(self.triggers.fail_on_nonzero_exit_code ? "true" : "false"),
      base64encode(self.triggers.fail_on_stderr ? "true" : "false"),
      base64encode(dirname("/") == "\\" ? self.triggers.command_windows : self.triggers.command_unix),
      base64encode(self.triggers.stdout_file),
      base64encode(self.triggers.stderr_file),
      base64encode(self.triggers.exit_code_file),
      base64encode("false"),
    ]))
    environment = merge(jsondecode(self.triggers.environment), jsondecode(self.triggers.sensitive_environment), var.triggerless_environment)
    working_dir = self.triggers.working_dir
  }

  // This provisioner runs the destroy command (triggers when the module is re-created or destroyed)
  provisioner "local-exec" {
    when = destroy
    command = join(" ", concat(dirname("/") == "\\" ? [
      "powershell.exe",
      "${abspath(path.module)}/run.ps1"
      ] : [
      "bash",
      "${abspath(path.module)}/run.sh"
      ], [
      base64encode(abspath("${path.module}/tmpfiles")),
      base64encode(self.triggers.uuid),
      base64encode(self.triggers.fail_on_nonzero_exit_code ? "true" : "false"),
      base64encode(self.triggers.fail_on_stderr ? "true" : "false"),
      base64encode(dirname("/") == "\\" ? self.triggers.command_when_destroy_windows : self.triggers.command_when_destroy_unix),
      base64encode("delete.${self.triggers.stdout_file}"),
      base64encode("delete.${self.triggers.stderr_file}"),
      base64encode("delete.${self.triggers.exit_code_file}"),
      base64encode("true"),
    ]))
    environment = merge(jsondecode(self.triggers.environment), jsondecode(self.triggers.sensitive_environment))
    working_dir = self.triggers.working_dir
  }
}

// These are the names of the files to read the results from
locals {
  stdout_file    = abspath("${path.module}/tmpfiles/${null_resource.shell.triggers.stdout_file}")
  stderr_file    = abspath("${path.module}/tmpfiles/${null_resource.shell.triggers.stderr_file}")
  exit_code_file = abspath("${path.module}/tmpfiles/${null_resource.shell.triggers.exit_code_file}")
}

// Read the stdout, stderr, and exit code from files
data "local_file" "stdout" {
  depends_on = [null_resource.shell]
  filename   = fileexists(local.stdout_file) ? local.stdout_file : "${path.module}/empty"
}
data "local_file" "stderr" {
  depends_on = [null_resource.shell]
  filename   = fileexists(local.stderr_file) ? local.stderr_file : "${path.module}/empty"
}
data "local_file" "exit_code" {
  depends_on = [null_resource.shell]
  filename   = fileexists(local.exit_code_file) ? local.exit_code_file : "${path.module}/empty"
}

// Use this as a resourced-based method to take an input that might change when the output files are missing,
// but the triggers haven't changed, and maintain the same output.
resource "random_id" "outputs" {
  // Reload the data when any of the main triggers change
  // We mark this as sensitive just so it doesn't have a massive output in the Terraform plan
  keepers     = sensitive(null_resource.shell.triggers)
  byte_length = 8
  // Feed the output values in as prefix. Then we can extract them from the output of this resource,
  // which will only change when the input triggers change
  // We mark this as sensitive just so it doesn't have a massive output in the Terraform plan
  prefix = sensitive("${jsonencode({
    stdout    = chomp(data.local_file.stdout.content)
    stderr    = chomp(data.local_file.stderr.content)
    exit_code = chomp(data.local_file.exit_code.content)
  })}${local.output_separator}")
  // Changes to the prefix shouldn't trigger a recreate, because when run again somewhere where the
  // original output files don't exist (but the shell triggers haven't changed), we don't want to
  // regenerate the output from non-existant files
  lifecycle {
    ignore_changes = [
      prefix
    ]
  }

  // Delete the files right away so they're not lingering on any local machine. The data has now
  // been saved in the state so we no longer need them.
  provisioner "local-exec" {
    when        = create
    interpreter = dirname("/") == "\\" ? ["powershell.exe"] : []
    command     = dirname("/") == "\\" ? "Remove-Item ${self.keepers.stdout_file}" : "rm ${self.keepers.stdout_file}"
    on_failure  = fail
    working_dir = "${path.module}/tmpfiles"
  }
  provisioner "local-exec" {
    when        = create
    interpreter = dirname("/") == "\\" ? ["powershell.exe"] : []
    command     = dirname("/") == "\\" ? "Remove-Item ${self.keepers.stderr_file}" : "rm ${self.keepers.stderr_file}"
    on_failure  = fail
    working_dir = "${path.module}/tmpfiles"
  }
  provisioner "local-exec" {
    when        = create
    interpreter = dirname("/") == "\\" ? ["powershell.exe"] : []
    command     = dirname("/") == "\\" ? "Remove-Item ${self.keepers.exit_code_file}" : "rm ${self.keepers.exit_code_file}"
    on_failure  = fail
    working_dir = "${path.module}/tmpfiles"
  }
}

locals {
  // Remove the random ID off the random ID and extract only the prefix
  outputs = jsondecode(split(local.output_separator, random_id.outputs.b64_std)[0])
}
