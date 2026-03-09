aws_region  = "us-west-2"
environment = "dev"
name_prefix = "inference"

accelerator_type        = "nvidia"
gpu_node_instance_types = ["g7e.12xlarge"]
node_group_size         = 2

# Option 2 later:
# gpu_node_instance_types = ["g7e.24xlarge"]
# node_group_size         = 1

# Regional fallback if G7e is unavailable:
# gpu_node_instance_types = ["g6e.12xlarge"]

system_node_instance_types = ["t3.large"]
system_node_group_size     = 1

node_disk_size        = 500
system_node_disk_size = 100

eks_admin_principal_arns = [
  "arn:aws:iam::123456789012:role/Admin",
]

tags = {
  Owner = "platform"
}
