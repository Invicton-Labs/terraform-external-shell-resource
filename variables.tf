variable "dynamic_depends_on" {
  description = "This input variable has the same function as the `depends_on` built-in variable, but has no restrictions on what kind of content it can contain."
  type        = any
  default     = null
}
locals {
  var_dynamic_depends_on = var.dynamic_depends_on
}

variable "command_unix" {
  description = "The command to run on creation when the module is used on a Unix machine. If not specified, will default to be the same as the `command_windows` variable."
  type        = string
  default     = null
}
locals {
  var_command_unix = var.command_unix
}

variable "command_windows" {
  description = "The command to run on creation when the module is used on a Windows machine. If not specified, will default to be the same as the `command_unix` variable."
  type        = string
  default     = null
}
locals {
  var_command_windows = var.command_windows
}

variable "command_destroy_unix" {
  description = "The command to run on destruction when the module is used on a Unix machine. If not specified, will default to be the same as the `command_destroy_windows` variable."
  type        = string
  default     = null
}
locals {
  var_command_destroy_unix = var.command_destroy_unix
}

variable "command_destroy_windows" {
  description = "The command to run on destruction when the module is used on a Windows machine. If not specified, will default to be the same as the `command_destroy_unix` variable."
  type        = string
  default     = null
}
locals {
  var_command_destroy_windows = var.command_destroy_windows
}

variable "triggers" {
  description = "A value (of any type) that, when changed, will cause the script to be re-run (will first run the destroy command if this module already exists in the state)."
  type        = any
  default     = {}
}
locals {
  var_triggers = var.triggers != null ? var.triggers : {}
}

variable "environment" {
  description = "Map of environment variables to pass to the command. This map will be merged with the `environment_sensitive` and `environment_triggerless` input variables (if either of them has the same key, those values will overwrite these values)."
  type        = map(string)
  default     = {}
}
locals {
  var_environment = var.environment != null ? var.environment : {}
}

variable "environment_sensitive" {
  description = "Map of (sentitive) environment variables to pass to the command. This map will be merged with the `environment` input variable (this overwrites those values with the same key) and `environment_triggerless` (those values overwrite these values with the same key)."
  type        = map(string)
  default     = {}
}
locals {
  var_environment_sensitive = var.environment_sensitive != null ? var.environment_sensitive : {}
}

variable "environment_triggerless" {
  description = "Map of environment variables to pass to the command, which will NOT trigger a resource re-create if changed. This map will be merged with the `environment` and `environment_sensitive` input variables (if either of them has the same key, these values will overwrite those values) for resource creation, but WILL NOT be provided for the destruction command."
  type        = map(string)
  default     = {}
}
locals {
  var_environment_triggerless = var.environment_triggerless != null ? var.environment_triggerless : {}
}

variable "working_dir" {
  description = "The working directory where command will be executed. Defaults to this module's install directory (usually somewhere in the `.terraform` directory)."
  type        = string
  default     = null
}
locals {
  var_working_dir = var.working_dir == "" ? null : var.working_dir
}

variable "fail_create_on_nonzero_exit_code" {
  description = "Whether a Terraform error should be thrown if the create command exits with a non-zero exit code. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the error code will be returned in `exit_code`."
  type        = bool
  default     = true
}
locals {
  var_fail_create_on_nonzero_exit_code = var.fail_create_on_nonzero_exit_code != null ? var.fail_create_on_nonzero_exit_code : true
}

variable "fail_create_on_timeout" {
  description = "Whether a Terraform error should be thrown if the create command times out (only applies if the `timeout_create` or `timeout_destroy` variable is provided). If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
  type        = bool
  default     = true
}
locals {
  var_fail_create_on_timeout = var.fail_create_on_timeout != null ? var.fail_create_on_timeout : true
}

variable "fail_create_on_stderr" {
  description = "Whether a Terraform error should be thrown if the create command outputs anything to stderr. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`. This is disabled by default because many commands write to stderr even if nothing went wrong."
  type        = bool
  default     = false
}
locals {
  var_fail_create_on_stderr = var.fail_create_on_stderr != null ? var.fail_create_on_stderr : false
}

variable "fail_destroy_on_nonzero_exit_code" {
  description = "Whether a Terraform error should be thrown if the destroy command exits with a non-zero exit code. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the error code will be returned in `exit_code`."
  type        = bool
  default     = true
}
locals {
  var_fail_destroy_on_nonzero_exit_code = var.fail_destroy_on_nonzero_exit_code != null ? var.fail_destroy_on_nonzero_exit_code : true
}

variable "fail_destroy_on_timeout" {
  description = "Whether a Terraform error should be thrown if the destroy command times out (only applies if the `timeout_create` or `timeout_destroy` variable is provided). If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
  type        = bool
  default     = true
}
locals {
  var_fail_destroy_on_timeout = var.fail_destroy_on_timeout != null ? var.fail_destroy_on_timeout : true
}

variable "fail_destroy_on_stderr" {
  description = "Whether a Terraform error should be thrown if the destroy command outputs anything to stderr. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
  type        = bool
  default     = false
}
locals {
  var_fail_destroy_on_stderr = var.fail_destroy_on_stderr != null ? var.fail_destroy_on_stderr : false
}

variable "timeout_create" {
  description = "The maximum number of seconds to allow the shell command to execute for on resource creation. If it exceeds this timeout, it will be killed and will fail. Leave as the default (`null`) or set as 0 for no timeout."
  type        = number
  default     = null
  validation {
    condition     = var.timeout_create == null ? true : var.timeout_create >= 0
    error_message = "The `timeout_create` input variable, if provided, must be greater than or equal to 0."
  }
}
locals {
  var_timeout_create = var.timeout_create == 0 ? null : var.timeout_create
}

variable "timeout_destroy" {
  description = "The maximum number of seconds to allow the shell command to execute for on resource destruction. If it exceeds this timeout, it will be killed and will fail. Leave as the default (`null`) or set as 0 for no timeout."
  type        = number
  default     = null
  validation {
    condition     = var.timeout_destroy == null ? true : var.timeout_destroy >= 0
    error_message = "The `timeout_destroy` input variable, if provided, must be greater than or equal to 0."
  }
}
locals {
  var_timeout_destroy = var.timeout_destroy == 0 ? null : var.timeout_destroy
}

variable "suppress_console" {
  description = "Whether to suppress the Terraform console output (including plan content and shell execution status messages) for this module. If enabled, much of the content will be hidden by marking it as \"sensitive\"."
  type        = bool
  default     = false
}
locals {
  var_suppress_console = var.suppress_console != null ? var.suppress_console : false
}

variable "unix_interpreter" {
  description = "The interpreter to use when running commands on a Unix-based system. This is primarily used for testing, and should usually be left to the default value."
  type        = string
  default     = "/bin/sh"
}
locals {
  var_unix_interpreter = var.unix_interpreter != null ? var.unix_interpreter : "/bin/sh"
}

variable "execution_id" {
  description = "A unique ID for the shell execution. Used for development only and will default to a UUID."
  type        = string
  default     = null
  validation {
    // Ensure that if an execution ID is provided, it matches the regex
    condition     = var.execution_id == null ? true : length(regexall("^[a-zA-Z0-9_. -]+$", trimspace(var.execution_id))) > 0
    error_message = "The `execution_id` input variable, if provided, must consist solely of letters, digits, hyphens, underscores, and spaces, and may not consist entirely of whitespace."
  }
}
locals {
  var_execution_id = var.execution_id
}
