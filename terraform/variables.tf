variable "snowflake_account" {
  description = "Snowflake account identifier (orgname-accountname)"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake admin user for Terraform"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake admin user password"
  type        = string
  sensitive   = true
}

variable "service_user_password" {
  description = "Password for GITHUB_ACTIONS_SERVICE_USER"
  type        = string
  sensitive   = true
}
