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

data "aws_iam_role" "autoscaling" {
  name = "AWSServiceRoleForAutoScaling"
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

resource "aws_autoscaling_group" "node" {
  desired_capacity        = var.desired_nodes
  launch_configuration    = aws_launch_configuration.node.id
  max_size                = var.maximum_nodes
  min_size                = var.minimum_nodes
  name_prefix             = var.node_name_prefix
  service_linked_role_arn = data.aws_iam_role.autoscaling.arn
  vpc_zone_identifier     = var.subnet_ids

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

resource "aws_iam_policy" "eks_autoscaling" {
  description = "EKS worker node autoscaling policy for cluster ${var.cluster_name}"
  name_prefix = "${var.node_name_prefix}-autoscaling"
  policy      = data.aws_iam_policy_document.autoscaling.json
}

resource "aws_iam_role_policy_attachment" "eks_autoscaling" {
  policy_arn = aws_iam_policy.eks_autoscaling.arn
  role       = aws_iam_role.node.id
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.id
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.id
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.id
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
    sid    = "eksWorkerAutoscalingOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

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
