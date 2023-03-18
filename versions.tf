terraform {
  // 0.15.0 - 0.15.3 had a bug where it threw an error if an output
  // was marked as sensitive.
  // 0.13.0 and 1.3.0 have bugs where it doesn't handle output correctly
  required_version = ">= 0.13.1, !=0.15.0, !=0.15.1, !=0.15.2, !=0.15.3, !=1.3.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 2.0.0"
    }
  }
}
