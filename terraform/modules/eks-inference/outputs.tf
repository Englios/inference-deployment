output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group attached to the cluster."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group attached to managed node groups."
  value       = module.eks.node_security_group_id
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN used for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID used by the cluster."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by worker nodes and the control plane."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs created for load balancers and NAT."
  value       = module.vpc.public_subnets
}

output "accelerator_type" {
  description = "The accelerator profile used by the worker node group."
  value       = var.accelerator_type
}
