resource "aws_autoscaling_group" "node" {
  count = length(var.subnet_ids)

  availability_zones      = [data.aws_subnet.subnet[count.index].availability_zone]
  desired_capacity        = var.desired_nodes_per_az
  launch_configuration    = aws_launch_configuration.node.id
  max_size                = var.maximum_nodes_per_az
  min_size                = var.minimum_nodes_per_az
  name_prefix             = var.node_name_prefix
  service_linked_role_arn = data.aws_iam_role.autoscaling.arn
  vpc_zone_identifier     = [data.aws_subnet.subnet[count.index].id]

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = var.node_name_prefix
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    propagate_at_launch = true
    value               = "owned"
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    propagate_at_launch = true
    value               = "owned"
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    propagate_at_launch = true
    value               = var.autoscaler_enabled
  }

  dynamic "tag" {
    for_each = var.extra_tags
    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = var.node_name_prefix
  role        = aws_iam_role.node.id
}

resource "aws_iam_role" "node" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
  name               = var.node_name_prefix

  tags = var.extra_tags
}

resource "aws_iam_policy" "eks" {
  description = "Collects policies from required managed policy documents"
  name_prefix = "${var.node_name_prefix}-eks"
  policy      = data.aws_iam_policy_document.eks.json
}

resource "aws_iam_policy" "eks_autoscaling" {
  description = "EKS worker node autoscaling policy for cluster ${var.cluster_name}"
  name_prefix = "${var.node_name_prefix}-autoscaling"
  policy      = data.aws_iam_policy_document.autoscaling.json
}

resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = aws_iam_policy.eks.arn
  role       = aws_iam_role.node.id
}

resource "aws_iam_role_policy_attachment" "eks_autoscaling" {
  policy_arn = aws_iam_policy.eks_autoscaling.arn
  role       = aws_iam_role.node.id
}

resource "aws_launch_configuration" "node" {
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.node.id
  image_id                    = var.image_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  name_prefix                 = var.node_name_prefix
  security_groups             = var.security_group_ids
  user_data                   = var.user_data

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "autoscaling" {
  statement {
    sid    = "eksWorkerAutoscalingAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    effect    = "Allow"
    resources = ["*"]
    sid       = "eksWorkerAutoscalingOwn"

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "eks" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:GetLifecyclePolicy",
      "ecr:GetLifecyclePolicyPreview",
      "ecr:ListTagsForResource",
      "ecr:DescribeImageScanFindings",
    ]

    effect    = "Allow"
    sid       = "AmazonEC2ContainerRegistryReadOnly"
    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:AssignPrivateIpAddresses",
      "ec2:AttachNetworkInterface",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes",
      "ec2:DetachNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:UnassignPrivateIpAddresses",
    ]

    effect    = "Allow"
    resources = ["*"]
    sid       = "AmazonEKSCNIPolicy1"
  }

  statement {
    actions   = ["ec2:CreateTags"]
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
    sid       = "AmazonEKSCNIPolicy2"
  }

  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
      "ec2:DescribeVpcs",
      "eks:DescribeCluster",
    ]

    effect    = "Allow"
    resources = ["*"]
    sid       = "AmazonEKSWorkerNodePolicy"
  }
}

data "aws_iam_role" "autoscaling" {
  name = "AWSServiceRoleForAutoScaling"
}

data "aws_subnet" "subnet" {
  count = length(var.subnet_ids)
  id    = var.subnet_ids[count.index]
}
