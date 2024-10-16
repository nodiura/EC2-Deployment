 #Define IAM Groups based on the workspace
resource "aws_iam_group" "db_admin" {
  name = "${terraform.workspace}-DBAdmin"
}
resource "aws_iam_group" "monitor" {
  name = "${terraform.workspace}-Monitor"
}
resource "aws_iam_group" "sysadmin" {
  name = "${terraform.workspace}-Sysadmin"
}
# Define IAM Users
variable "db_admin_users" {
  type    = list(string)
  default = ["dbadmin1", "dbadmin2"]
}
variable "monitor_users" {
  type    = list(string)
  default = ["monitoruser1", "monitoruser2", "monitoruser3", "monitoruser4"]
}
variable "sysadmin_users" {
  type    = list(string)
  default = ["sysadmin1", "sysadmin2"]
}
# Combine users into a single map that indicates their groups
locals {
  user_group_map = merge(
    { for user in var.db_admin_users : user => aws_iam_group.db_admin.name },
    { for user in var.monitor_users : user => aws_iam_group.monitor.name },
    { for user in var.sysadmin_users : user => aws_iam_group.sysadmin.name }
  )
}