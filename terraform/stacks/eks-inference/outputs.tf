output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_inference.cluster_name
}

output "aws_region" {
  description = "AWS region used for the stack."
  value       = var.aws_region
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint."
  value       = module.eks_inference.cluster_endpoint
}

output "cluster_version" {
  description = "EKS control plane version."
  value       = module.eks_inference.cluster_version
}

output "vpc_id" {
  description = "Cluster VPC ID."
  value       = module.eks_inference.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets used by the cluster."
  value       = module.eks_inference.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnets created for the cluster."
  value       = module.eks_inference.public_subnet_ids
}
