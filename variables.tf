variable "autoscaler_enabled" {
  default = "false"
}

variable "cluster_name" {}
variable "desired_nodes_per_az" {}
variable "extra_tags" {
  default = {}
  type    = map(string)
}

variable "image_id" {}
variable "instance_type" {
  default = "m5.xlarge"
}

variable "key_name" {
  default = ""
}

variable "maximum_nodes_per_az" {
  default = 8
}

variable "minimum_nodes_per_az" {
  default = 0
}

variable "node_name_prefix" {}
variable "security_group_ids" {
  type = list(string)
}

variable "subnet_ids" {
  type = list(string)
}

variable "user_data" {
  default = ""
}
