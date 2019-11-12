resource "aws_iam_role" "ecsTaskRole" {
  for_each = { for k, v in var.service_apps : k => v }

  name = "${each.key}_ecsTaskRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {}
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  for_each = { for k, v in var.service_apps : k => v }

  name = "${each.key}_ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {}
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "AmazonECSTaskExecutionRolePolicy" {
  for_each = { for k, v in aws_iam_role.ecsTaskExecutionRole : k => v }

  role       = aws_iam_role.ecsTaskExecutionRole[each.key].name
  policy_arn = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn

  depends_on = [
    aws_iam_role.ecsTaskExecutionRole,
  ]
}


resource "aws_ecr_repository" "repo" {
  for_each = { for k, v in var.service_apps : k => v }
  name     = each.key
}

resource "aws_ecr_repository_policy" "repo" {
  for_each   = { for k, v in aws_ecr_repository.repo : k => v }
  repository = aws_ecr_repository.repo[each.key].name

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "${aws_ecr_repository.repo[each.key].name}",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
        }
    ]
}
EOF

  depends_on = [
    aws_ecr_repository.repo,
  ]
}

locals {
  service_name = length(keys(var.service_settings)) > 0 ? element(keys(var.service_settings), 0) : ""
}

resource "aws_ecs_cluster" "cls" {
  for_each = { for k, v in var.service_settings : k => v }

  name = each.key
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_region" "current" {}


resource "aws_ecs_task_definition" "app" {
  for_each = { for k, v in var.service_apps : k => v }

  family                   = each.key
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "1024"
  memory                   = "2048"
  # task_role_arn            = aws_iam_role.ecsTaskRole[each.key].arn
  # execution_role_arn       = aws_iam_role.ecsTaskExecutionRole[each.key].arn

  container_definitions = <<EOT
[
  {
    "image": "nginx:latest",
    "name": "${each.key}",
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ]
  }
]
EOT

}



data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_launch_configuration" "as_conf" {
  name_prefix   = "terraform-lc-example-"
  image_id      = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }

  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.cls[local.service_name].name} >> /etc/ecs/ecs.config
EOF
}

resource "aws_autoscaling_group" "bar" {
  name                 = "terraform-asg-example"
  launch_configuration = "${aws_launch_configuration.as_conf.name}"
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = var.aws_vpc_subnets_private.*.id

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group" "ecs_srv" {
  for_each    = { for k, v in var.service_apps : k => v }
  name        = "${each.key}-ecstask"
  description = "SecurityGroup that manages the ingress and egress connections from/to ${each.key} ECS Service"
  vpc_id      = var.aws_vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "app" {
  for_each = { for k, v in var.service_apps : k => v }

  name                    = "${each.key}-nginx-proxy"
  cluster                 = aws_ecs_cluster.cls[local.service_name].id
  task_definition         = aws_ecs_task_definition.app[each.key].arn
  desired_count           = "1"
  launch_type             = "EC2"
  propagate_tags          = "TASK_DEFINITION"
  enable_ecs_managed_tags = true

  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 75

  network_configuration {
    security_groups  = [aws_security_group.ecs_srv[each.key].id]
    subnets          = var.aws_vpc_subnets_private.*.id
    assign_public_ip = false
  }

  load_balancer {
    # target_group_arn = aws_alb_target_group.app_ecs_fargate[each.key].arn
    elb_name       = var.service_apps_lb[each.key].name
    container_name = each.key
    container_port = 80
  }

  # health_check_grace_period_seconds = 5

  tags = {
    "ecs_service"                     = each.key
    "ecs_cluster"                     = aws_ecs_cluster.cls[local.service_name].id
    "active_task_definition_name"     = aws_ecs_task_definition.app[each.key].family
    "active_task_definition_revision" = aws_ecs_task_definition.app[each.key].revision
  }

  depends_on = [
    aws_ecs_cluster.cls,
    aws_ecs_task_definition.app,
    aws_security_group.ecs_srv,
    # aws_alb_target_group.app_ecs_fargate,
  ]
}
