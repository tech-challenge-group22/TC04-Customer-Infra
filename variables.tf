
variable "db_username" {
  description = "Database administrator username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable prefix {
  type        = string
  default     = "TC04"
}

variable cluster_name {
  type        = string
  default     = "TC04-Customer"
}

variable desired_size {
  default     = 2
}

variable min_size {
  default     = 2
}

variable max_size {
  default     = 4
}

variable retention_days {
  default     = 30
}

