variable "command_unix" {
  description = "The command to run on creation when the module is used on a Unix machine. If not specified, will default to be the same as the `command_windows` variable."
  type        = string
  default     = null
}

variable "command_windows" {
  description = "The command to run on creation when the module is used on a Windows machine. If not specified, will default to be the same as the `command_unix` variable."
  type        = string
  default     = null
}

variable "command_destroy_unix" {
  description = "The command to run on destruction when the module is used on a Unix machine. If not specified, will default to be the same as the `command_destroy_windows` variable."
  default     = null
}

variable "command_destroy_windows" {
  description = "The command to run on destruction when the module is used on a Windows machine. If not specified, will default to be the same as the `command_destroy_unix` variable."
  default     = null
}

variable "triggers" {
  description = "A value (of any type) that, when changed, will cause the script to be re-run (will first run the destroy command if this module already exists in the state)."
  type        = any
  default     = ""
}

variable "environment" {
  type        = map(string)
  default     = {}
  description = "Map of environment variables to pass to the command. Will be merged with `sensitive_environment` and `triggerless_environment` (if either of them has the same key, those values will overwrite these values)."
}

variable "sensitive_environment" {
  type        = map(string)
  default     = {}
  description = "Map of (sentitive) environment variables to pass to the command. Will be merged with `environment` (this overwrites those values with the same key) and `triggerless_environment` (those values overwrite these values with the same key)."
}

variable "triggerless_environment" {
  type        = map(string)
  default     = {}
  description = "Map of environment variables to pass to the command, which will NOT trigger a resource re-create if changed. Will be merged with `environment` and `sensitive_environment` (if either of them has the same key, these values will overwrite those values) for resource creation, but WILL NOT be provided for the destruction command."
}

variable "working_dir" {
  type        = string
  default     = ""
  description = "The working directory where command will be executed."
}

variable "fail_create_on_nonzero_exit_code" {
  type        = bool
  default     = true
  description = "Whether a Terraform error should be thrown if the create command exits with a non-zero exit code. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the error code will be returned in `exit_code`."
}

variable "fail_create_on_timeout" {
  type        = bool
  default     = true
  description = "Whether a Terraform error should be thrown if the create command times out (only applies if the `timeout_create` or `timeout_destroy` variable is provided). If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
}

variable "fail_create_on_stderr" {
  type        = bool
  default     = false
  description = "Whether a Terraform error should be thrown if the create command outputs anything to stderr. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`. This is disabled by default because many commands write to stderr even if nothing went wrong."
}

variable "fail_destroy_on_nonzero_exit_code" {
  type        = bool
  default     = true
  description = "Whether a Terraform error should be thrown if the destroy command exits with a non-zero exit code. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the error code will be returned in `exit_code`."
}

variable "fail_destroy_on_timeout" {
  type        = bool
  default     = true
  description = "Whether a Terraform error should be thrown if the destroy command times out (only applies if the `timeout_create` or `timeout_destroy` variable is provided). If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
}

variable "fail_destroy_on_stderr" {
  type        = bool
  default     = false
  description = "Whether a Terraform error should be thrown if the destroy command outputs anything to stderr. If true, nothing will be returned from this module and Terraform will fail the apply. If false, the error message will be returned in `stderr` and the exit code will be returned in `exit_code`."
}

variable "timeout_create" {
  type = number
  default = null
  description = "The maximum number of seconds to allow the shell command to execute for on resource creation. If it exceeds this timeout, it will be killed and will fail. Leave as the default (`null`) for no timeout."
}

variable "timeout_destroy" {
  type = number
  default = null
  description = "The maximum number of seconds to allow the shell command to execute for on resource destruction. If it exceeds this timeout, it will be killed and will fail. Leave as the default (`null`) for no timeout."
}

variable "track_version" {
  type        = bool
  default     = false
  description = "Whether to track the version number of the shell resource. If `true`, this module will output an auto-incrementing number that increases by 1 every time the shell command is re-run."
}

variable "dynamic_depends_on" {
  type = any
  default = null
  description = "Has the same function as the built-in Terraform `depends_on` parameter, except that it can reference dynamic values as well."
}

variable "debug" {
  type = bool
  default = false
  description = "Whether to output debug content into a special debug file (stored within this module's \"$${path.module}/tmpfiles\" directory) that does not get deleted after completing the apply. Usually only useful for development of this module."
}

variable "suppress_console" {
  type = bool
  default = false
  description = "Whether to suppress the Terraform console output (including plan content and shell execution status messages) for this module. If enabled, much of the content will be hidden by marking it as \"sensitive\"."
}
