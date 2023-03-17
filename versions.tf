terraform {
  // 0.15.0 - 0.15.3 had a bug where it threw an error if an output
  // was marked as sensitive.
  required_version = ">= 0.13, !=0.15.0, !=0.15.1, !=0.15.2, !=0.15.3"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 2.0.0"
    }
  }
}
