// This is a UUID that represents a single instance of this module
resource "random_uuid" "execution_id" {}

locals {
  // If an execution ID was provided, it's debug mode
  is_debug = false // local.var_execution_id != null

  // Use the input execution ID if one was provided; otherwise, use the UUID we created for this module
  execution_id = local.var_execution_id != null ? local.var_execution_id : random_uuid.execution_id.result

  // Check whether we're currently running on Windows
  is_windows = dirname("/") == "\\"

  # These are commands that have no effect
  null_command_unix    = ":"
  null_command_windows = "% ':'"

  // If command_unix is specified, use it. Otherwise, if command_windows is specified, use it. Otherwise, use a command that does nothing
  command_create_unix = replace(replace(chomp(local.var_command_unix != null ? local.var_command_unix : (local.var_command_windows != null ? local.var_command_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  // If command_windows is specified, use it. Otherwise, if command_unix is specified, use it. Otherwise, use a command that does nothing
  command_create_windows = replace(replace(chomp(local.var_command_windows != null ? local.var_command_windows : (local.var_command_unix != null ? local.var_command_unix : local.null_command_windows)), "\r", ""), "\r\n", "\n")
  // If command_destroy_unix is specified, use it. Otherwise, if command_windows is specified, use it. Otherwise, use a command that does nothing
  command_destroy_unix = replace(replace(chomp(local.var_command_destroy_unix != null ? local.var_command_destroy_unix : (local.var_command_destroy_windows != null ? local.var_command_destroy_windows : local.null_command_unix)), "\r", ""), "\r\n", "\n")
  // If command_destroy_windows is specified, use it. Otherwise, if command_unix is specified, use it. Otherwise, use a command that does nothing
  command_destroy_windows = replace(replace(chomp(local.var_command_destroy_windows != null ? local.var_command_destroy_windows : (local.var_command_destroy_unix != null ? local.var_command_destroy_unix : local.null_command_windows)), "\r", ""), "\r\n", "\n")

  // Check whether there would be any command to execute on this operating system
  create_command_exists = local.is_windows ? local.command_create_windows != local.null_command_windows : local.command_create_unix != local.null_command_unix

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

  // This is ONLY used for calculating the max command line length on Windows systems.
  all_environment_b64 = base64encode(join(";", [
    for k, v in merge(local.env_vars, local.env_vars_sensitive, local.env_vars_triggerless) :
    "${base64encode(k)}:${base64encode(v)}"
  ]))

  temp_dir = "tmpfiles"

  // The input trigger can be a simple string or a JSON-encoded object
  input_triggers = try(tostring(local.var_triggers), jsonencode(local.var_triggers))

  partial_triggers = {
    // If the triggers change, that obviously triggers a re-create
    triggers = local.input_triggers

    // These should never change unless the module itself is destroyed/tainted, but we need
    // them in the trigger so that they can be referenced with the "self" variable
    // in the provisioners
    execution_id         = local.execution_id
    null_command_unix    = local.null_command_unix
    null_command_windows = local.null_command_windows

    is_debug = local.is_debug ? "true" : "false"

    // If any of the commands change, that's a recreate.
    // The create commands don't need to be stored in trigger state, so we can use the sha256 of them.
    command_create_unix     = sha256(local.command_create_unix)
    command_create_windows  = sha256(local.command_create_windows)
    command_destroy_unix    = local.command_destroy_unix
    command_destroy_windows = local.command_destroy_windows

    // Different timeouts need re-create
    timeout_create  = local.var_timeout_create == null ? 0 : local.var_timeout_create
    timeout_destroy = local.var_timeout_destroy == null ? 0 : local.var_timeout_destroy

    command_create_filename_windows  = "${local.execution_id}.create.ps1"
    command_destroy_filename_windows = "${local.execution_id}.destroy.ps1"
    env_var_file_create              = "${local.execution_id}.create.env"
    env_var_file_destroy             = "${local.execution_id}.destroy.env"
    stdout_file                      = "${local.execution_id}.stdout"
    stderr_file                      = "${local.execution_id}.stderr"
    exitcode_file                    = "${local.execution_id}.exitcode"
    temp_dir                         = local.temp_dir

    // If we want to handle errors differently, that needs a re-create
    fail_create_on_nonzero_exit_code  = local.var_fail_create_on_nonzero_exit_code == true ? "true" : "false"
    fail_create_on_stderr             = local.var_fail_create_on_stderr == true ? "true" : "false"
    fail_create_on_timeout            = local.var_fail_create_on_timeout == true ? "true" : "false"
    fail_destroy_on_nonzero_exit_code = local.var_fail_destroy_on_nonzero_exit_code == true ? "true" : "false"
    fail_destroy_on_stderr            = local.var_fail_destroy_on_stderr == true ? "true" : "false"
    fail_destroy_on_timeout           = local.var_fail_destroy_on_timeout == true ? "true" : "false"

    // If the environment variables change
    // We jsonencode because the `triggers`/`keepers` expect a map of string
    environment = jsonencode(local.env_vars)

    // Only mark it as sensitive if anything is actually sensitive
    // The `try` is to support versions of Terraform that don't support `sensitive`
    environment_sensitive = jsonencode(local.env_vars_sensitive)

    // If the working directory changes, that needs a re-create
    // The triggers field will remove any values that are `null`, so we have to
    // switch it to an empty string if it's null.
    working_dir = local.var_working_dir != null ? local.var_working_dir : ""

    // The interpreter to use on Unix-based systems
    unix_interpreter = local.var_unix_interpreter
  }

  // Args that are always passed in, regarless of Windows/Linux or Create/Destroy
  input_args_common = [
    base64encode(local.execution_id),
    base64encode("${abspath(path.module)}/${local.temp_dir}"),
    base64encode(local.partial_triggers.is_debug),
    base64encode(local.partial_triggers.stdout_file),
    base64encode(local.partial_triggers.stderr_file),
    base64encode(local.partial_triggers.exitcode_file),
    base64encode(local.partial_triggers.unix_interpreter),
  ]

  // Full args for creating with direct input. These are ONLY used for calculating
  // the max command line length on Windows systems.
  input_args_create_direct_windows = join("|", concat([
    // uses_input_files
    base64encode("false"),
    // is_create
    base64encode("true"),
    // environment
    local.all_environment_b64,
    // command
    base64encode(local.command_create_windows),
    base64encode(local.partial_triggers.timeout_create),
    base64encode(local.partial_triggers.fail_create_on_nonzero_exit_code),
    base64encode(local.partial_triggers.fail_create_on_stderr),
    base64encode(local.partial_triggers.fail_create_on_timeout),
  ], local.input_args_common))

  input_args_destroy_direct_windows = join("|", concat([
    // uses_input_files
    base64encode("false"),
    // is_create
    base64encode("false"),
    // environment
    local.all_environment_b64,
    // command
    base64encode(local.command_destroy_windows),
    base64encode(local.partial_triggers.timeout_destroy),
    base64encode(local.partial_triggers.fail_destroy_on_nonzero_exit_code),
    base64encode(local.partial_triggers.fail_destroy_on_stderr),
    base64encode(local.partial_triggers.fail_destroy_on_timeout),
  ], local.input_args_common))

  // These are the complete commands as they would be used with direct inputs (not file inputs)
  command_line_create_direct_windows  = "powershell.exe ${abspath(path.module)}/run.ps1 \"${local.input_args_create_direct_windows}\""
  command_line_destroy_direct_windows = "${local.var_unix_interpreter} ${abspath(path.module)}/run.sh \"${local.input_args_destroy_direct_windows}\""

  // These are all of the things that, if they change, trigger a re-create
  all_triggers = merge(local.partial_triggers, {
    // PowerShell has a max command line length of 8191 characters. We'll trim it to an 7000 char limit.
    // If the total length of the Windows command line inputs exceed this limit, we need to use the file input mode.
    // We include this in the triggers so the provisioners have easy access to this data.
    windows_file_input_create_required  = local.command_create_windows != local.null_command_windows && length(local.command_line_create_direct_windows) > 7000
    windows_file_input_destroy_required = local.command_destroy_windows != local.null_command_windows && length(local.command_line_destroy_direct_windows) > 7000
  })

  // We mark it as sensitive so it doesn't have a massive output in the Terraform plan
  // The `try` is so we can support earlier versions of Terraform that don't support `sensitive`
  triggers = local.var_suppress_console && !local.is_debug ? try(sensitive(local.all_triggers), local.all_triggers) : local.all_triggers

  // Windows command file write commands
  windows_command_file_create_command  = <<EOF
[System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.command_create_filename_windows}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.command_create_windows)}")))
[System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.env_var_file_create}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${local.all_environment_b64}")))
EOF
  windows_command_file_destroy_command = <<EOF
[System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.command_destroy_filename_windows}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.command_destroy_windows)}")))
[System.IO.File]::WriteAllText([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode("${abspath(path.module)}/${local.temp_dir}/${local.all_triggers.env_var_file_destroy}")}")), [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${local.all_environment_b64}")))
EOF

  // Commands that must be run to create command and environment files for Windows
  windows_file_commands = local.is_windows ? flatten([
    local.all_triggers.windows_file_input_create_required ? [local.windows_command_file_create_command] : [],
    local.all_triggers.windows_file_input_destroy_required ? [local.windows_command_file_destroy_command] : [],
  ]) : []
}

// Write the commands to temp files, if necessary
module "write_command_files" {
  source  = "Invicton-Labs/shell-data/external"
  version = "~>0.4.1"

  // Output files to this module's path, not the called module's path
  working_dir = path.module

  // If there are any Windows file creation commands required, use them; otherwise, do a null command.
  command_windows = length(local.windows_file_commands) > 0 ? join("\n", local.windows_file_commands) : local.null_command_windows

  // Command files are never used on Unix since it doesn't have a command line input length limit
  command_unix = local.null_command_unix

  timeout                   = 10
  fail_on_nonzero_exit_code = true
  fail_on_stderr            = true
  fail_on_timeout           = true
}

resource "null_resource" "shell" {
  depends_on = [
    // Don't try to run the commands until the command files have been written
    module.write_command_files,
  ]

  // This ternary forces the execution to wait for the `dynamic_depends_on`
  triggers = jsonencode(local.var_dynamic_depends_on) == "" ? local.triggers : local.triggers

  // This provisioner runs the main command
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    interpreter = flatten(dirname("/") == "\\" ? [
      local.command_create_windows == self.triggers.null_command_windows ? [
        "powershell.exe",
        ] : [
        "powershell.exe",
        "-File",
        "${abspath(path.module)}/run.ps1",
      ]
      ] : [
      local.command_create_unix == self.triggers.null_command_unix ? [
        self.triggers.unix_interpreter,
        "-c",
        ] : [
        self.triggers.unix_interpreter,
        "${abspath(path.module)}/run.sh",
      ]
    ])
    command = (
      dirname("/") == "\\" ? local.command_create_windows == self.triggers.null_command_windows : local.command_create_unix == self.triggers.null_command_unix
      ) ? (
      // If it is, run a null command that doesn't do anything. Don't bother sending all of the arguments.
      dirname("/") == "\\" ? self.triggers.null_command_windows : self.triggers.null_command_unix
      ) : join("|", [
        // uses_input_files. Only true if running on Windows AND the command line length is too long for Windows.
        base64encode(dirname("/") == "\\" && self.triggers.windows_file_input_create_required ? "true" : "false"),
        // is_create
        base64encode("true"),
        // environment
        base64encode(dirname("/") == "\\" && self.triggers.windows_file_input_create_required ? self.triggers.env_var_file_create : join(";", [
          for k, v in merge(jsondecode(self.triggers.environment), jsondecode(self.triggers.environment_sensitive), local.var_environment_triggerless) :
          "${base64encode(k)}:${base64encode(v)}"
        ])),
        // command
        base64encode(dirname("/") == "\\" ? (self.triggers.windows_file_input_create_required ? self.triggers.command_create_filename_windows : local.command_create_windows) : local.command_create_unix),
        base64encode(self.triggers.timeout_create),
        base64encode(self.triggers.fail_create_on_nonzero_exit_code),
        base64encode(self.triggers.fail_create_on_stderr),
        base64encode(self.triggers.fail_create_on_timeout),
        base64encode(self.triggers.execution_id),
        base64encode("${abspath(path.module)}/${self.triggers.temp_dir}"),
        base64encode(self.triggers.is_debug),
        base64encode(self.triggers.stdout_file),
        base64encode(self.triggers.stderr_file),
        base64encode(self.triggers.exitcode_file),
        base64encode(self.triggers.unix_interpreter),
    ])
    working_dir = self.triggers.working_dir == "" ? null : self.triggers.working_dir
  }

  // This provisioner runs the destroy command (triggers when the module is re-created or destroyed)
  provisioner "local-exec" {
    when       = destroy
    on_failure = fail
    interpreter = flatten(dirname("/") == "\\" ? [
      self.triggers.command_destroy_windows == self.triggers.null_command_windows ? [
        "powershell.exe",
        ] : [
        "powershell.exe",
        "-File",
        "${abspath(path.module)}/run.ps1",
      ]
      ] : [
      self.triggers.command_destroy_unix == self.triggers.null_command_unix ? [
        self.triggers.unix_interpreter,
        "-c",
        ] : [
        self.triggers.unix_interpreter,
        "${abspath(path.module)}/run.sh",
      ]
    ])
    command = (
      dirname("/") == "\\" ? self.triggers.command_destroy_windows == self.triggers.null_command_windows : self.triggers.command_destroy_unix == self.triggers.null_command_unix
      ) ? (
      // If it is, run a null command that doesn't do anything. Don't bother sending all of the arguments.
      dirname("/") == "\\" ? self.triggers.null_command_windows : self.triggers.null_command_unix
      ) : join("|", [
        // uses_input_files. Only true if running on Windows AND the command line length is too long for Windows.
        base64encode(dirname("/") == "\\" && self.triggers.windows_file_input_destroy_required ? "true" : "false"),
        // is_create
        base64encode("false"),
        // environment
        base64encode(dirname("/") == "\\" && self.triggers.windows_file_input_destroy_required ? self.triggers.env_var_file_destroy : join(";", [
          for k, v in merge(jsondecode(self.triggers.environment), jsondecode(self.triggers.environment_sensitive)) :
          "${base64encode(k)}:${base64encode(v)}"
        ])),
        // command
        base64encode(dirname("/") == "\\" ? (self.triggers.windows_file_input_destroy_required ? self.triggers.command_destroy_filename_windows : self.triggers.command_destroy_windows) : self.triggers.command_destroy_unix),
        base64encode(self.triggers.timeout_destroy),
        base64encode(self.triggers.fail_destroy_on_nonzero_exit_code),
        base64encode(self.triggers.fail_destroy_on_stderr),
        base64encode(self.triggers.fail_destroy_on_timeout),
        base64encode(self.triggers.execution_id),
        base64encode("${abspath(path.module)}/${self.triggers.temp_dir}"),
        base64encode(self.triggers.is_debug),
        base64encode(self.triggers.stdout_file),
        base64encode(self.triggers.stderr_file),
        base64encode(self.triggers.exitcode_file),
        base64encode(self.triggers.unix_interpreter),
    ])
    working_dir = self.triggers.working_dir == "" ? null : self.triggers.working_dir
  }
}

// These are the names of the files to read the results from
locals {
  stdout_file                  = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.stdout_file}")
  stderr_file                  = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.stderr_file}")
  exit_code_file               = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.exitcode_file}")
  command_create_file_windows  = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.command_create_filename_windows}")
  command_destroy_file_windows = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.command_destroy_filename_windows}")
  env_var_file_create          = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.env_var_file_create}")
  env_var_file_destroy         = abspath("${path.module}/${local.temp_dir}/${null_resource.shell.triggers.env_var_file_destroy}")

  // These ternary checks just force Terraform to wait for the resource to finish executing the provisioners before checking for and reading the files.
  stdout_content   = fileexists(null_resource.shell.id == null ? null : local.stdout_file) ? file(null_resource.shell.id == null ? null : local.stdout_file) : ""
  stderr_content   = fileexists(null_resource.shell.id == null ? null : local.stderr_file) ? file(null_resource.shell.id == null ? null : local.stderr_file) : ""
  exitcode_content = fileexists(null_resource.shell.id == null ? null : local.exit_code_file) ? file(null_resource.shell.id == null ? null : local.exit_code_file) : ""

  // Replace all "\r\n" (considered by Terraform to be a single character) with "\n", and remove any extraneous "\r".
  // This helps ensure a consistent output across platforms.
  stdout       = local.stdout_content == "" ? "" : trimsuffix(replace(replace(local.stdout_content, "\r", ""), "\r\n", "\n"), "\n")
  stderr       = local.stderr_content == "" ? "" : trimsuffix(replace(replace(local.stderr_content, "\r", ""), "\r\n", "\n"), "\n")
  exitcode_str = local.exitcode_content == "" ? "" : trimspace(replace(replace(local.exitcode_content, "\r", ""), "\r\n", "\n"))
  exitcode     = !local.create_command_exists ? 0 : local.exitcode_str == "" ? "" : local.exitcode_str == "null" ? null : tonumber(local.exitcode_str)
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
}

// Delete the files that are used during create
module "delete_files" {
  source  = "Invicton-Labs/shell-data/external"
  version = "~>0.4.1"

  depends_on = [
    random_id.outputs
  ]

  working_dir = path.module

  command_windows = <<EOF
  $_stdout_file = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.stdout_file)}"))
  if (Test-Path -Path $_stdout_file) { Remove-Item -Path $_stdout_file }

  $_stderr_file = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.stderr_file)}"))
  if (Test-Path -Path $_stderr_file) { Remove-Item -Path $_stderr_file }

  $_exitcode_file = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.exit_code_file)}"))
  if (Test-Path -Path $_exitcode_file) { Remove-Item -Path $_exitcode_file }

  $_command_create_file_windows = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.command_create_file_windows)}"))
  if (Test-Path -Path $_command_create_file_windows) { Remove-Item -Path $_command_create_file_windows }

  $_env_var_file = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${base64encode(local.env_var_file_create)}"))
  if (Test-Path -Path $_env_var_file) { Remove-Item -Path $_env_var_file }
EOF

  command_unix = <<EOF
# This checks if we're running on MacOS
_kernel_name="$(uname -s)"
case "$${_kernel_name}" in
    darwin*|Darwin*)    
        # It's MacOS.
        # Mac doesn't support the "-d" flag for base64 decoding, 
        # so we have to use the full "--decode" flag instead.
        _decode_flag="--decode" ;;
    *)
        # It's NOT MacOS.
        # Not all Linux base64 installs (e.g. BusyBox) support the full
        # "--decode" flag. So, we use "-d" here, since it's supported
        # by everything except MacOS.
        _decode_flag="-d" ;;
esac

rm -f "$(echo "${base64encode(local.stdout_file)}" | base64 $_decode_flag)"
rm -f "$(echo "${base64encode(local.stderr_file)}" | base64 $_decode_flag )"
rm -f "$(echo "${base64encode(local.exit_code_file)}" | base64 $_decode_flag)"
rm -f "$(echo "${base64encode(local.command_create_file_windows)}" | base64 $_decode_flag)"
rm -f "$(echo "${base64encode(local.env_var_file_create)}" | base64 $_decode_flag)"
EOF

  timeout                   = 10
  fail_on_nonzero_exit_code = true
  fail_on_stderr            = true
  fail_on_timeout           = true
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
