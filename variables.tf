variable "cluster_name" {}
variable "desired_nodes" {}
variable "extra_tags" {
  default = {}
  type    = "map"
}

variable "image_id" {}
variable "instance_type" {
  default = "m5.xlarge"
}

variable "key_name" {
  default = ""
}

variable "maximum_nodes" {
  default = 8
}

variable "minimum_nodes" {
  default = 0
}

variable "node_name_prefix" {}
variable "security_group_ids" {
  type = "list"
}

variable "subnet_ids" {}
variable "user_data" {
  default = ""
}
