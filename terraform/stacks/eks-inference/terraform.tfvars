aws_region   = "us-west-2"
environment  = "dev"
name_prefix  = "inference"

accelerator_type = "nvidia"
gpu_node_instance_types = ["g5.xlarge"]
node_group_size = 2

# Malaysia fallback example:
# aws_region              = "ap-southeast-5"
# gpu_node_instance_types = ["g6.xlarge"]

system_node_instance_types = ["t3.large"]
system_node_group_size     = 1

eks_admin_principal_arns = [
  "arn:aws:iam::123456789012:role/Admin",
]

tags = {
  Owner = "platform"
}
