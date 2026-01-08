# TFLint Configuration for MLOps Platform
# https://github.com/terraform-linters/tflint

config {
  # Enable module inspection
  module = true

  # Force all rules to emit errors
  force = false
}

# Terraform rules
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS rules
plugin "aws" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Azure rules
plugin "azurerm" {
  enabled = true
  version = "0.25.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Google Cloud rules
plugin "google" {
  enabled = true
  version = "0.26.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Require description for variables
rule "terraform_documented_variables" {
  enabled = true
}

# Require description for outputs
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn on deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Comment syntax
rule "terraform_comment_syntax" {
  enabled = true
}