module "eks_inference" {
  source = "../../modules/eks-inference"

  name_prefix                     = var.name_prefix
  environment                     = var.environment
  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_enabled_log_types       = var.cluster_enabled_log_types
  vpc_cidr                        = var.vpc_cidr
  az_count                        = var.az_count
  public_subnet_cidrs             = var.public_subnet_cidrs
  private_subnet_cidrs            = var.private_subnet_cidrs
  enable_nat_gateway              = var.enable_nat_gateway
  single_nat_gateway              = var.single_nat_gateway
  gpu_node_instance_types         = var.gpu_node_instance_types
  system_node_instance_types      = var.system_node_instance_types
  node_group_size                 = var.node_group_size
  system_node_group_size          = var.system_node_group_size
  node_disk_size                  = var.node_disk_size
  system_node_disk_size           = var.system_node_disk_size
  node_group_labels               = var.node_group_labels
  enable_ebs_csi                  = var.enable_ebs_csi
  eks_admin_principal_arns        = var.eks_admin_principal_arns
  tags                            = var.tags
}
