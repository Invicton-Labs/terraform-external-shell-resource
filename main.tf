// This is a UUID that represents a single instance of this module
resource "random_uuid" "uuid" {}

locals {
  is_windows = dirname("/") == "\\"
  # These are commands that have no effect
  null_command_unix    = ":"
  null_command_windows = "% ':'"

  command_unix            = replace(replace(chomp(var.command_unix != null ? var.command_unix : (var.command_windows != null ? var.command_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  command_windows         = chomp(var.command_windows != null ? var.command_windows : (var.command_unix != null ? var.command_unix : local.null_command_windows))
  command_destroy_unix    = replace(replace(chomp(var.command_destroy_unix != null ? var.command_destroy_unix : (var.command_destroy_windows != null ? var.command_destroy_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  command_destroy_windows = chomp(var.command_destroy_windows != null ? var.command_destroy_windows : (var.command_destroy_unix != null ? var.command_destroy_unix : local.null_command_windows))

  // The input trigger can be a simple string or a JSON-encoded object
  input_triggers = try(tostring(var.triggers), jsonencode(var.triggers))

  // These are all of the things that, if they change, trigger a re-create
  all_triggers = {
    // If the triggers change, that obviously triggers a re-create
    triggers = local.input_triggers
    // If any of the commands change
    command_unix            = local.command_unix
    command_windows         = local.command_windows
    command_destroy_unix    = local.command_destroy_unix
    command_destroy_windows = local.command_destroy_windows

    // If the environment variables change
    // We jsonencode because the `triggers`/`keepers` expect a map of string
    environment = jsonencode(var.environment)
    // Only mark it as sensitive if anything is actually sensitive
    sensitive_environment = length(var.sensitive_environment) > 0 ? sensitive(jsonencode(var.sensitive_environment)) : jsonencode({})

    // If the working directory changes
    working_dir = var.working_dir

    // If we want to handle errors differently, that needs a re-create
    fail_create_on_nonzero_exit_code  = var.fail_create_on_nonzero_exit_code
    fail_create_on_stderr             = var.fail_create_on_stderr
    fail_create_on_timeout            = var.fail_create_on_timeout
    fail_destroy_on_nonzero_exit_code = var.fail_destroy_on_nonzero_exit_code
    fail_destroy_on_stderr            = var.fail_destroy_on_stderr
    fail_destroy_on_timeout           = var.fail_destroy_on_timeout

    // Different timeouts need re-create
    timeout_create  = var.timeout_create == null ? 0 : (var.timeout_create < 0 ? 0 : var.timeout_create)
    timeout_destroy = var.timeout_destroy == null ? 0 : (var.timeout_destroy < 0 ? 0 : var.timeout_destroy)

    // These should never change unless the module itself is destroyed/tainted, but we need
    // them in the trigger so that they can be referenced with the "self" variable
    // in the provisioners
    uuid           = random_uuid.uuid.result
    stdout_file    = "${random_uuid.uuid.result}.stdout"
    stderr_file    = "${random_uuid.uuid.result}.stderr"
    exit_code_file = "${random_uuid.uuid.result}.exitcode"

    debug = var.debug
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

module "dynamic_depends_on" {
  source             = "./dynamic-depends-on"
  dynamic_depends_on = var.dynamic_depends_on
}

resource "null_resource" "shell" {
  depends_on = [
    module.dynamic_depends_on
  ]

  // We mark it as sensitive so it doesn't have a massive output in the Terraform plan
  triggers = var.suppress_console ? sensitive(local.all_triggers) : local.all_triggers

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
      self.triggers.uuid,
      self.triggers.fail_create_on_nonzero_exit_code ? 1 : 0,
      self.triggers.fail_create_on_stderr ? 1 : 0,
      self.triggers.fail_create_on_timeout ? 1 : 0,
      base64encode(dirname("/") == "\\" ? self.triggers.command_windows : self.triggers.command_unix),
      self.triggers.stdout_file,
      self.triggers.stderr_file,
      self.triggers.exit_code_file,
      self.triggers.timeout_create,
      0,
      self.triggers.debug ? 1 : 0,
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
      self.triggers.uuid,
      self.triggers.fail_destroy_on_nonzero_exit_code ? 1 : 0,
      self.triggers.fail_destroy_on_stderr ? 1 : 0,
      self.triggers.fail_destroy_on_timeout ? 1 : 0,
      base64encode(dirname("/") == "\\" ? self.triggers.command_destroy_windows : self.triggers.command_destroy_unix),
      "${self.triggers.stdout_file}.destroy",
      "${self.triggers.stderr_file}.destroy",
      "${self.triggers.exit_code_file}.destroy",
      self.triggers.timeout_destroy,
      1,
      self.triggers.debug ? 1 : 0,
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

  stdout_content   = fileexists(null_resource.shell.id == null ? null : local.stdout_file) ? file(null_resource.shell.id == null ? null : local.stdout_file) : ""
  stderr_content   = fileexists(null_resource.shell.id == null ? null : local.stderr_file) ? file(null_resource.shell.id == null ? null : local.stderr_file) : ""
  exitcode_content = chomp(replace(replace(replace(fileexists(null_resource.shell.id == null ? null : local.exit_code_file) ? file(null_resource.shell.id == null ? null : local.exit_code_file) : "", "\r", ""), "\r\n", ""), "\n", ""))
}

// Use this as a resourced-based method to take an input that might change when the output files are missing,
// but the triggers haven't changed, and maintain the same output.
resource "random_id" "outputs" {
  // Always wait for everything to be done with the external shell before we try to store or delete anything
  depends_on = [
    null_resource.shell
  ]
  // Reload the data when any of the main triggers change
  // We use a hash so it doesn't have a massive output in the Terraform plan
  keepers     = sensitive(null_resource.shell.triggers)
  byte_length = 8
  // Feed the output values in as prefix. Then we can extract them from the output of this resource,
  // which will only change when the input triggers change
  // We mark this as sensitive just so it doesn't have a massive output in the Terraform plan
  prefix = sensitive("${jsonencode({
    // These ternary operators just force Terraform to wait for the shell execution to be complete before trying to read the file contents
    stdout = local.stdout_content
    stderr = local.stderr_content
    // Replace any CR, LF, or CRLF characters with empty strings. We just want to read the exit code number
    exit_code = local.exitcode_content
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
    interpreter = local.stdout_content == null ? null : (local.is_windows ? ["powershell.exe"] : [])
    command     = local.is_windows ? "if (Test-Path -Path ${local.stdout_file}) { Remove-Item -Path ${local.stdout_file} }" : "rm -f ${local.stdout_file}"
    on_failure  = fail
  }
  provisioner "local-exec" {
    when        = create
    interpreter = local.stderr_content == null ? null : (local.is_windows ? ["powershell.exe"] : [])
    command     = local.is_windows ? "if (Test-Path -Path ${local.stderr_file}) { Remove-Item -Path ${local.stderr_file} }" : "rm -f ${local.stderr_file}"
    on_failure  = fail
  }
  provisioner "local-exec" {
    when        = create
    interpreter = local.exitcode_content == null ? null : (local.is_windows ? ["powershell.exe"] : [])
    command     = local.is_windows ? "if (Test-Path -Path ${local.exit_code_file}) { Remove-Item -Path ${local.exit_code_file} }" : "rm -f ${local.exit_code_file}"
    on_failure  = fail
  }
}

locals {
  // Remove the random ID off the random ID and extract only the prefix
  outputs = jsondecode(split(local.output_separator, random_id.outputs.b64_std)[0])
}
