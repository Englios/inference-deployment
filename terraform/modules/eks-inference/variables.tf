variable "name_prefix" {
  description = "Prefix used for AWS resources."
  type        = string
  default     = "inference"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Optional explicit EKS cluster name. When null, a derived name is used."
  type        = string
  default     = null
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access" {
  description = "Whether to expose the EKS API endpoint publicly."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Whether to expose the EKS API endpoint privately inside the VPC."
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "Control plane log types to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "How many availability zones to use."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "public_subnet_cidrs" {
  description = "Optional explicit public subnet CIDRs. Must match az_count when set."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == var.az_count
    error_message = "public_subnet_cidrs must be empty or contain az_count entries."
  }
}

variable "private_subnet_cidrs" {
  description = "Optional explicit private subnet CIDRs. Must match az_count when set."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == var.az_count
    error_message = "private_subnet_cidrs must be empty or contain az_count entries."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways for private subnets."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT gateway for all AZs to reduce cost."
  type        = bool
  default     = true
}

variable "gpu_node_instance_types" {
  description = "GPU instance types for NVIDIA-backed inference nodes."
  type        = list(string)
  default     = ["g7e.12xlarge"]
}

variable "system_node_instance_types" {
  description = "General-purpose instance types for the untained system node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_group_size" {
  description = "Fixed desired/min/max size for the inference managed node group."
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_size >= 1
    error_message = "node_group_size must be at least 1."
  }
}

variable "system_node_group_size" {
  description = "Fixed desired/min/max size for the untained system managed node group."
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_group_size >= 1
    error_message = "system_node_group_size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for each worker node."
  type        = number
  default     = 500
}

variable "system_node_disk_size" {
  description = "Root EBS volume size in GiB for each system node."
  type        = number
  default     = 100
}

variable "node_group_labels" {
  description = "Additional Kubernetes labels to apply to the inference managed node group."
  type        = map(string)
  default     = {}
}

variable "enable_ebs_csi" {
  description = "Whether to install the aws-ebs-csi-driver addon with IRSA."
  type        = bool
  default     = true
}

variable "eks_admin_principal_arns" {
  description = "IAM principal ARNs that should receive cluster admin access entries."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all supported AWS resources."
  type        = map(string)
  default     = {}
}
