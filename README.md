# Terraform Shell (Resource)

On the Terraform Registry: [Invicton-Labs/shell-resource/external](https://registry.terraform.io/modules/Invicton-Labs/shell-resource/external/latest)

This module allows generic shell commands to be run as a resource (will only re-run when an input variable changes). It supports both Linux and Windows (Mac currently untested, but *should* be supported) and requires no external dependencies. This is a complete rewrite of the [original module from Matti Paksula](https://github.com/matti/terraform-shell-resource); it offers many new features and fixes one of the major issues with the old module, which was that the outputs would not be updated on a trigger change.

This module is a workaround for https://github.com/hashicorp/terraform/issues/610, please give it a 👍 so we don't need this module anymore.

For Windows, this module should work on any system that supports a relatively modern version of PowerShell. For Unix, this module should work on any system that supports `sed` and `base64` (which is the vast majority of out-of-the-box systems).

For a module that has the same functionality but runs as a data source instead (re-runs every plan/apply), see [this module](https://registry.terraform.io/modules/Invicton-Labs/shell-data/external/latest).

## Example use cases
- Integration of existing shell scripts that you use regularly
- Use of the AWS CLI to do things that the Terraform AWS provider does not yet support
- Integration of other installed tools such as `openssl`
- Whatever your heart desires

## Limitations
- For use on macOS, the `coreutils` package must be installed and `timeout` must be created as an alias for `gtimeout`

## Usage

**Note:** if only one of `command_unix` or `command_windows` is provided, that one will be used on all operating systems. The same applies for `command_destroy_unix` and `command_destroy_windows`.

```
module "shell_resource_hello" {
  source  = "Invicton-Labs/shell-resource/external"

  // The command to run on resource creation on Unix machines
  command_unix         = "echo \"$TEXT $MORETEXT from $ORIGINAL_CREATED_TIME\""

  // The command to run on resource creation on Windows machines
  command_windows = "Write-Host \"$env:TEXT $env:MORETEXT from $env:ORIGINAL_CREATED_TIME\""

  // The command to run on resource destruction on Unix machines
  command_destroy_unix         = "echo \"$TEXT $MORETEXT\""

  // The command to run on resource destruction on Windows machines
  command_destroy_windows = "Write-Host \"$env:TEXT $env:MORETEXT\""

  // The directory to run the command in
  working_dir     = path.root

  // If the command exits with a non-zero exit code, kill Terraform.
  // This is enabled by default because generally we want our commands to succeed.
  fail_create_on_nonzero_exit_code = true

  // We can optionally also kill Terraform if the command writes anything to stderr.
  // This is disabled by default because many commands write to stderr even if nothing went wrong.
  fail_create_on_stderr = false

  // The same variables exist for destroy commands
  fail_destroy_on_nonzero_exit_code = true
  fail_destroy_on_stderr = false

  // We can optionally set a timeout; if the command runs longer than this, it will be killed
  // There are separate timeouts for the create and destroy steps
  timeout_create = 120
  timeout_destroy = 60

  // By default, the apply will fail on a timeout, but we can optionally override that
  fail_create_on_timeout = false
  fail_destroy_on_timeout = false

  // Environment variables (will appear in base64-encoded form in the Terraform plan output)
  environment = {
    TEXT     = "Hello"
    DESTROY_TEXT = "Goodbye"
  }

  // Environment variables (will be hidden in the Terraform plan output)
  sensitive_environment = {
    MORETEXT = "World"
  }

  // Environment variables that, when changed, will not trigger a re-create
  triggerless_environment = {
    ORIGINAL_CREATED_TIME = timestamp()
  }
}

output "stdout" {
  value = module.shell_resource_hello.stdout
}
output "stderr" {
  value = module.shell_resource_hello.stderr
}
output "exitstatus" {
  value = module.shell_resource_hello.exit_code
}
```

```
...
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

exitstatus = 0
stderr = ""
stdout = "Hello World from 2022-03-06T06:22:14Z"
```

## Related issues:
 - https://github.com/hashicorp/terraform/issues/610
 - https://github.com/hashicorp/terraform/issues/17337
 - https://github.com/hashicorp/terraform/issues/6830
 - https://github.com/hashicorp/terraform/issues/17034
 - https://github.com/hashicorp/terraform/issues/10878
 - https://github.com/hashicorp/terraform/issues/8136
 - https://github.com/hashicorp/terraform/issues/18197
 - https://github.com/hashicorp/terraform/issues/17862
