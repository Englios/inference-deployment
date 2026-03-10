locals {
  name = "${var.name_prefix}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "inference-engine-deployment"
    },
    var.tags,
  )

  cluster_name = coalesce(var.cluster_name, "${local.name}-eks")

  public_subnet_cidrs  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [for idx in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnet_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [for idx in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, idx + 100)]

  accelerator_profile = {
    ami_type       = "AL2023_x86_64_NVIDIA"
    instance_types = var.gpu_node_instance_types
    labels = {
      workload                         = "inference"
      accelerator                      = "nvidia-gpu"
      "node.kubernetes.io/accelerator" = "nvidia"
    }
    taints = {
      inference = {
        key    = "dedicated"
        value  = "inference"
        effect = "NO_SCHEDULE"
      }
    }
  }

  addons = merge(
    {
      coredns = {
        most_recent = true
      }
      kube-proxy = {
        most_recent = true
      }
      vpc-cni = {
        before_compute = true
        most_recent    = true
      }
      eks-pod-identity-agent = {
        before_compute = true
        most_recent    = true
      }
    },
    var.enable_ebs_csi ? {
      aws-ebs-csi-driver = {
        most_recent              = true
        service_account_role_arn = module.ebs_csi_driver_irsa[0].arn
      }
    } : {},
  )
}
