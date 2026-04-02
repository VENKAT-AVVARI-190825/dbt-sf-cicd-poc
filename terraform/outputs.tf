output "dev_database" {
  value = snowflake_database.dev.name
}

output "prod_database" {
  value = snowflake_database.prod.name
}

output "dataops_role" {
  value = snowflake_role.dataops.name
}

output "warehouse_xs" {
  value = snowflake_warehouse.xs.name
}

output "warehouse_md" {
  value = snowflake_warehouse.md.name
}

output "service_user" {
  value = snowflake_user.github_actions.name
}
