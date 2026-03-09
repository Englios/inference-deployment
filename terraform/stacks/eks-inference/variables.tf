variable "aws_region" {
  description = "AWS region for the EKS cluster."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix used for AWS resources."
  type        = string
  default     = "inference"
}

variable "environment" {
  description = "Environment name for naming and tagging."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Optional explicit EKS cluster name."
  type        = string
  default     = null
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS endpoint is publicly accessible."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Whether the EKS endpoint is privately accessible."
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "Control plane logs to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use."
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "Optional explicit public subnet CIDRs."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Optional explicit private subnet CIDRs."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Whether to use a single shared NAT gateway."
  type        = bool
  default     = true
}

variable "accelerator_type" {
  description = "Node accelerator type: nvidia or neuron."
  type        = string
  default     = "nvidia"
}

variable "gpu_node_instance_types" {
  description = "GPU instance types for NVIDIA-backed nodes."
  type        = list(string)
  default     = ["g7e.12xlarge"]
}

variable "system_node_instance_types" {
  description = "General-purpose instance types for untained system nodes."
  type        = list(string)
  default     = ["t3.large"]
}

variable "neuron_node_instance_types" {
  description = "Inferentia instance types for Neuron-backed nodes."
  type        = list(string)
  default     = ["inf2.xlarge"]
}

variable "node_group_size" {
  description = "Fixed desired/min/max size for the inference node group."
  type        = number
  default     = 2
}

variable "system_node_group_size" {
  description = "Fixed desired/min/max size for the system node group."
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Node root volume size in GiB."
  type        = number
  default     = 500
}

variable "system_node_disk_size" {
  description = "System node root volume size in GiB."
  type        = number
  default     = 100
}

variable "node_group_labels" {
  description = "Additional node labels for the managed node group."
  type        = map(string)
  default = {
    distributed-test = "true"
  }
}

variable "enable_ebs_csi" {
  description = "Whether to install the EBS CSI addon."
  type        = bool
  default     = true
}

variable "eks_admin_principal_arns" {
  description = "IAM user or role ARNs that should get EKS admin access."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default     = {}
}
