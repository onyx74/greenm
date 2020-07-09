# specific variable
variable "region" {
    description = "AWS Region"
    type        = string
    default     = "us-east-1"
}

variable "key_name" {
    default = "appkey"
}

variable "jump_host_ami" {
    default = "ami-0ac80df6eff0e70b5"
}

variable "instance_ami" {
    default = "ami-0995a0271a0703eee"
}

variable "instance_type" {
    default = "t3.small"
}

#
# Network specific variable
#

variable "alb_name" {
    default = "pet-alb"
}

variable "target_group_name" {
    default = "target-group"
}
