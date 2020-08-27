terraform {
  required_version = ">= 0.12.0"
}

resource "aws_autoscaling_group" "node" {
  count = length(var.subnet_ids)

  availability_zones      = slice(data.aws_subnet.subnet.*.availability_zone, count.index, count.index + 1)
  desired_capacity        = var.desired_nodes
  max_size                = var.maximum_nodes
  min_size                = var.minimum_nodes
  name                    = "${var.node_name_prefix}-${element(data.aws_subnet.subnet.*.availability_zone, count.index)}"
  service_linked_role_arn = data.aws_iam_role.autoscaling.arn
  vpc_zone_identifier     = slice(data.aws_subnet.subnet.*.id, count.index, count.index + 1)

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.node.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type     = override.value
          weighted_capacity = 1
        }
      }
    }
  }

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

resource "aws_launch_template" "node" {
  image_id                             = var.image_id
  instance_type                        = var.instance_types[0]
  key_name                             = var.key_name
  instance_initiated_shutdown_behavior = "terminate"
  name                                 = var.node_name_prefix
  user_data                            = base64encode(var.user_data)
  vpc_security_group_ids               = var.security_group_ids

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  monitoring {
    enabled = true
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
