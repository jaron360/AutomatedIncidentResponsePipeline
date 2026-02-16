variable "vpc_name" {
  description = "Name/environment of VPC"
  type        = string
  default     = "development"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.16.0.0/16"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Your desired environment"
  type        = string
  default     = "development"
}
