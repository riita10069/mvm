variable "region" {
  description = "Region for the MicroVM image and everything it needs."
  type        = string
  default     = "ap-northeast-1"
}

variable "name" {
  description = "MicroVM image name. `mvm up -i <name>` starts VMs from it."
  type        = string
  default     = "mvm"
}

variable "base_image_version" {
  description = "Major version of the Lambda-managed base image al2023-1 (a single number, e.g. 1)."
  type        = string
  default     = "1"
}

variable "minimum_memory_mib" {
  description = "Minimum VM memory (al2023-1 accepts 512-8192)."
  type        = number
  default     = 2048
}

variable "log_retention_days" {
  type    = number
  default = 30
}
