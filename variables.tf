variable "autoscaler_enabled" {
  default = false
  type    = bool
}

variable "cluster_name" {}
variable "desired_nodes" {
  default = 0
  type    = number
}

variable "extra_tags" {
  default = {}
  type    = map(string)
}

variable "image_id" {}

variable "instance_types" {
  type = list(string)
}

variable "key_name" {
  default = ""
}

variable "maximum_nodes" {
  default = 8
  type    = number
}

variable "minimum_nodes" {
  default = 0
  type    = number
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
