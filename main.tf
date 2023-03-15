// This is a UUID that represents a single instance of this module
resource "random_uuid" "execution_id" {}

locals {
  // If an execution ID was provided, it's debug mode
  is_debug = local.var_execution_id != null

  // Use the input execution ID if one was provided; otherwise, use the UUID we created for this module
  execution_id = local.var_execution_id != null ? local.var_execution_id : random_uuid.execution_id.result

  is_windows = dirname("/") == "\\"
  # These are commands that have no effect
  null_command_unix    = ":"
  null_command_windows = "% ':'"

  // If command_unix is specified, use it. Otherwise, if command_windows is specified, use it. Otherwise, use a command that does nothing
  command_unix = replace(replace(chomp(local.var_command_unix != null ? local.var_command_unix : (local.var_command_windows != null ? local.var_command_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  // If command_windows is specified, use it. Otherwise, if command_unix is specified, use it. Otherwise, use a command that does nothing
  command_windows = replace(replace(chomp(local.var_command_windows != null ? local.var_command_windows : (local.var_command_unix != null ? local.var_command_unix : local.null_command_windows)), "\r", ""), "\r\n", "\n")
  // If command_destroy_unix is specified, use it. Otherwise, if command_windows is specified, use it. Otherwise, use a command that does nothing
  command_destroy_unix = replace(replace(chomp(local.var_command_destroy_unix != null ? local.var_command_destroy_unix : (local.var_command_destroy_windows != null ? local.var_command_destroy_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  // If command_destroy_windows is specified, use it. Otherwise, if command_unix is specified, use it. Otherwise, use a command that does nothing
  command_destroy_windows = replace(replace(chomp(local.var_command_destroy_windows != null ? local.var_command_destroy_windows : (local.var_command_destroy_unix != null ? local.var_command_destroy_unix : local.null_command_windows)), "\r", ""), "\r\n", "\n")

  // Create versions of the environment variables with all carriage returns removed
  env_vars = {
    for k, v in local.var_environment :
    k => replace(replace(v, "\r", ""), "\r\n", "\n")
  }
  env_vars_sensitive = {
    for k, v in local.var_environment_sensitive :
    k => replace(replace(v, "\r", ""), "\r\n", "\n")
  }
  env_vars_triggerless = {
    for k, v in local.var_environment_triggerless :
    k => replace(replace(v, "\r", ""), "\r\n", "\n")
  }

  all_environment_b64 = base64encode(join(";", [
    for k, v in merge(local.env_vars, local.env_vars_sensitive, local.env_vars_triggerless) :
    "${base64encode(k)}:${base64encode(v)}"
  ]))

  temp_dir = "tmpfiles"

  // The input trigger can be a simple string or a JSON-encoded object
  input_triggers = try(tostring(local.var_triggers), jsonencode(local.var_triggers))

  // These are all of the things that, if they change, trigger a re-create
  all_triggers = {
    // If the triggers change, that obviously triggers a re-create
    triggers = local.input_triggers

    // If any of the commands change.
    command_unix         = local.command_unix
    command_destroy_unix = local.command_destroy_unix
    // We can uses hashes because the commands aren't passed through triggers,
    // they're written separately to files.
    command_windows         = sha256(local.command_windows)
    command_destroy_windows = sha256(local.command_destroy_windows)

    // If the environment variables change
    // We jsonencode because the `triggers`/`keepers` expect a map of string
    environment = sha256(jsonencode(local.env_vars))

    // Only mark it as sensitive if anything is actually sensitive
    // The `try` is to support versions of Terraform that don't support `sensitive`
    environment_sensitive = sha256(jsonencode(local.env_vars_sensitive))

    // If the working directory changes, that needs a re-create
    // The triggers field will remove any values that are `null`, so we have to
    // switch it to an empty string if it's null.
    working_dir = local.var_working_dir != null ? local.var_working_dir : ""

    // If we want to handle errors differently, that needs a re-create
    fail_create_on_nonzero_exit_code  = local.var_fail_create_on_nonzero_exit_code == true ? "true" : "false"
    fail_create_on_stderr             = local.var_fail_create_on_stderr == true ? "true" : "false"
    fail_create_on_timeout            = local.var_fail_create_on_timeout == true ? "true" : "false"
    fail_destroy_on_nonzero_exit_code = local.var_fail_destroy_on_nonzero_exit_code == true ? "true" : "false"
    fail_destroy_on_stderr            = local.var_fail_destroy_on_stderr == true ? "true" : "false"
    fail_destroy_on_timeout           = local.var_fail_destroy_on_timeout == true ? "true" : "false"

    // Different timeouts need re-create
    timeout_create  = local.var_timeout_create == null ? 0 : local.var_timeout_create
    timeout_destroy = local.var_timeout_destroy == null ? 0 : local.var_timeout_destroy

    // The interpreter to use on Unix-based systems
    unix_interpreter = local.var_unix_interpreter

    // These should never change unless the module itself is destroyed/tainted, but we need
    // them in the trigger so that they can be referenced with the "self" variable
    // in the provisioners
    execution_id                 = local.execution_id
    command_create_file_windows  = "${local.execution_id}.create.ps1"
    command_destroy_file_windows = "${local.execution_id}.destroy.ps1"
    env_var_file                 = "${local.execution_id}.env"
    stdout_file                  = "${local.execution_id}.stdout"
    stderr_file                  = "${local.execution_id}.stderr"
    exitcode_file                = "${local.execution_id}.exitcode"
    temp_dir                     = local.temp_dir

    is_debug = local.is_debug == true ? "true" : "false"
  }

  // We mark it as sensitive so it doesn't have a massive output in the Terraform plan
  // The `try` is so we can support earlier versions of Terraform that don't support `sensitive`
  triggers = local.var_suppress_console && !local.is_debug ? try(sensitive(local.all_triggers), local.all_triggers) : local.all_triggers
}

// Write the commands to temp files
module "write_command_files" {
  source  = "Invicton-Labs/shell-data/external"
  version = "~>0.4.1"

  // Output files to this module's path, not the called module's path
  working_dir = path.module

  command_windows = <<EOF
  $_content = 
  [System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.command_create_file_windows}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.command_windows)}")))
  [System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.command_destroy_file_windows}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.command_destroy_windows)}")))
  [System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.env_var_file}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${local.all_environment_b64}")))
EOF

  command_unix = <<EOF
# This checks if we're running on MacOS
_kernel_name="$(uname -s)"
case "$${_kernel_name}" in
    darwin*|Darwin*)    
        # It's MacOS.
        # Mac doesn't support the "-d" flag for base64 decoding, 
        # so we have to use the full "--decode" flag instead.
        _decode_flag="--decode"
    *)
        # It's NOT MacOS.
        # Not all Linux base64 installs (e.g. BusyBox) support the full
        # "--decode" flag. So, we use "-d" here, since it's supported
        # by everything except MacOS.
        _decode_flag="-d"
esac

base64 $_decode_flag "${local.all_environment_b64}" > $(base64 $_decode_flag "${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.env_var_file}")}")
EOF

  timeout                   = 10
  fail_on_nonzero_exit_code = true
  fail_on_stderr            = true
  fail_on_timeout           = true
}

resource "null_resource" "shell" {
  depends_on = [
    // Don't try to run the commands until the command files have been written
    module.write_command_files
  ]

  // This ternary forces the execution to wait for the `dynamic_depends_on`
  triggers = jsonencode(local.var_dynamic_depends_on) == "" ? local.triggers : local.triggers

  // This provisioner runs the main command
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = "${dirname("/") == "\\" ? "powershell.exe ${abspath(path.module)}/run.ps1" : "${self.triggers.unix_interpreter} ${abspath(path.module)}/run.sh"} \"${join("|", [
      base64encode(self.triggers.execution_id),
      base64encode("${abspath(path.module)}/${self.triggers.temp_dir}"),
      base64encode(self.triggers.env_var_file),
      base64encode(self.triggers.timeout_create),
      base64encode(self.triggers.fail_create_on_nonzero_exit_code),
      base64encode(self.triggers.fail_create_on_stderr),
      base64encode(self.triggers.fail_create_on_timeout),
      base64encode(self.triggers.is_debug),
      base64encode(dirname("/") == "\\" ? self.triggers.command_create_file_windows : self.triggers.command_unix),
      // is_create
      base64encode("true"),
      base64encode(self.triggers.stdout_file),
      base64encode(self.triggers.stderr_file),
      base64encode(self.triggers.exitcode_file),
      base64encode(self.triggers.unix_interpreter),
    ])}\""
    working_dir = self.triggers.working_dir == "" ? null : self.triggers.working_dir
  }

  // This provisioner runs the destroy command (triggers when the module is re-created or destroyed)
  provisioner "local-exec" {
    when       = destroy
    on_failure = fail
    command = "${dirname("/") == "\\" ? "powershell.exe ${abspath(path.module)}/run.ps1" : "${self.triggers.unix_interpreter} ${abspath(path.module)}/run.sh"} \"${join("|", [
      base64encode(self.triggers.execution_id),
      base64encode("${abspath(path.module)}/${self.triggers.temp_dir}"),
      base64encode(self.triggers.env_var_file),
      base64encode(self.triggers.timeout_destroy),
      base64encode(self.triggers.fail_destroy_on_nonzero_exit_code),
      base64encode(self.triggers.fail_destroy_on_stderr),
      base64encode(self.triggers.fail_destroy_on_timeout),
      base64encode(self.triggers.is_debug),
      base64encode(dirname("/") == "\\" ? self.triggers.command_destroy_file_windows : self.triggers.command_destroy_unix),
      // is_create
      base64encode("false"),
      base64encode(self.triggers.stdout_file),
      base64encode(self.triggers.stderr_file),
      base64encode(self.triggers.exitcode_file),
      base64encode(self.triggers.unix_interpreter),
    ])}\""
    working_dir = self.triggers.working_dir == "" ? null : self.triggers.working_dir
  }
}

// These are the names of the files to read the results from
locals {
  stdout_file    = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.stdout_file}")
  stderr_file    = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.stderr_file}")
  exit_code_file = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.exitcode_file}")

  stdout_content   = fileexists(null_resource.shell.id == null ? null : local.stdout_file) ? file(null_resource.shell.id == null ? null : local.stdout_file) : ""
  stderr_content   = fileexists(null_resource.shell.id == null ? null : local.stderr_file) ? file(null_resource.shell.id == null ? null : local.stderr_file) : ""
  exitcode_content = fileexists(null_resource.shell.id == null ? null : local.exit_code_file) ? file(null_resource.shell.id == null ? null : local.exit_code_file) : ""

  // Replace all "\r\n" (considered by Terraform to be a single character) with "\n", and remove any extraneous "\r".
  // This helps ensure a consistent output across platforms.
  stdout       = local.stdout_content == "" ? "" : trimsuffix(replace(replace(local.stdout_content, "\r", ""), "\r\n", "\n"), "\n")
  stderr       = local.stderr_content == "" ? "" : trimsuffix(replace(replace(local.stderr_content, "\r", ""), "\r\n", "\n"), "\n")
  exitcode_str = local.exitcode_content == "" ? "" : trimspace(replace(replace(local.exitcode_content, "\r", ""), "\r\n", "\n"))
  exitcode     = local.exitcode_str == "" ? "" : local.exitcode_str == "null" ? null : tonumber(local.exitcode_str)
}

locals {
  output_str = "${base64encode(jsonencode({
    stdout    = local.stdout
    stderr    = local.stderr
    exit_code = local.exitcode
  }))}|"
}

// Use this as a resource-based method to take an input that might change when the output files are missing,
// but the triggers haven't changed, and maintain the same output.
resource "random_id" "outputs" {
  // Always wait for everything to be done with the external shell before we try to store or delete anything
  depends_on = [
    null_resource.shell
  ]
  // Reload the data when any of the main triggers change
  // We use a hash so it doesn't have a massive output in the Terraform plan
  keepers     = try(sensitive(null_resource.shell.triggers), null_resource.shell.triggers)
  byte_length = 1

  // Feed the output values in as prefix. Then we can extract them from the output of this resource,
  // which will only change when the input triggers change
  // We mark this as sensitive just so it doesn't have a massive output in the Terraform plan
  prefix = try(sensitive(local.output_str), local.output_str)

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
    interpreter = local.stdout_content == null ? null : (local.is_windows ? ["powershell.exe"] : ["/bin/sh"])
    command     = local.is_windows ? "if (Test-Path -Path ${local.stdout_file}) { Remove-Item -Path ${local.stdout_file} }" : "rm -f ${local.stdout_file}"
    on_failure  = fail
  }
  provisioner "local-exec" {
    when        = create
    interpreter = local.stderr_content == null ? null : (local.is_windows ? ["powershell.exe"] : ["/bin/sh"])
    command     = local.is_windows ? "if (Test-Path -Path ${local.stderr_file}) { Remove-Item -Path ${local.stderr_file} }" : "rm -f ${local.stderr_file}"
    on_failure  = fail
  }
  provisioner "local-exec" {
    when        = create
    interpreter = local.exitcode_content == null ? null : (local.is_windows ? ["powershell.exe"] : ["/bin/sh"])
    command     = local.is_windows ? "if (Test-Path -Path ${local.exit_code_file}) { Remove-Item -Path ${local.exit_code_file} }" : "rm -f ${local.exit_code_file}"
    on_failure  = fail
  }
  # provisioner "local-exec" {
  #   when        = create
  #   interpreter = local.exitcode_content == null ? null : (local.is_windows ? ["powershell.exe"] : ["/bin/sh"])
  #   command     = local.is_windows ? "if (Test-Path -Path ${local.command_create_file_windows}) { Remove-Item -Path ${local.command_create_file_windows} }" : "rm -f ${local.command_create_file_unix}"
  #   on_failure  = fail
  # }
  # provisioner "local-exec" {
  #   when        = create
  #   interpreter = local.exitcode_content == null ? null : (local.is_windows ? ["powershell.exe"] : ["/bin/sh"])
  #   command     = local.is_windows ? "if (Test-Path -Path ${local.command_destroy_file_windows}) { Remove-Item -Path ${local.command_destroy_file_windows} }" : "rm -f ${local.command_destroy_file_unix}"
  #   on_failure  = fail
  # }
}

locals {
  // Remove the random ID off the random ID and extract only the prefix
  outputs = jsondecode(base64decode(split("|", random_id.outputs.b64_std)[0]))

  // This checks if the stdout/stderr contains any of the values of the `environment_sensitive` input variable.
  // We use `replace` to check for the presence, even though the recommended tool is `regexall`, because
  // we don't control what the search string is, so it could be a regex pattern, but we want to treat
  // it as a literal.
  stdout_contains_sensitive = length([
    for k, v in local.var_environment_sensitive :
    true
    if length(replace(local.outputs.stdout, v, "")) != length(local.outputs.stdout)
  ]) > 0
  stderr_contains_sensitive = length([
    for k, v in local.var_environment_sensitive :
    true
    if length(replace(local.outputs.stderr, v, "")) != length(local.outputs.stderr)
  ]) > 0

  // The `try` is to support versions of Terraform that don't support `sensitive`.
  stdout_censored = local.stdout_contains_sensitive ? try(sensitive(local.outputs.stdout), local.outputs.stdout) : local.outputs.stdout
  stderr_censored = local.stderr_contains_sensitive ? try(sensitive(local.outputs.stderr), local.outputs.stderr) : local.outputs.stderr
}
