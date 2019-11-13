resource "aws_iam_role" "ecs-ec2-role" {
  for_each = { for k, v in var.service_apps : k => v }

  name = "${each.key}_ecs-ec2-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs-ec2-role" {
  for_each = { for k, v in var.service_apps : k => v }
  name     = "${each.key}_ecs-ec2-role"
  role     = aws_iam_role.ecs-ec2-role[each.key].name

  depends_on = [aws_iam_role.ecs-ec2-role]
}

resource "aws_iam_role_policy" "ecs-ec2-role-policy" {
  for_each = { for k, v in var.service_apps : k => v }

  name = "${each.key}_ecs-ec2-role-policy"

  role = aws_iam_role.ecs-ec2-role[each.key].name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "ecs:CreateCluster",
              "ecs:DeregisterContainerInstance",
              "ecs:DiscoverPollEndpoint",
              "ecs:Poll",
              "ecs:RegisterContainerInstance",
              "ecs:StartTelemetrySession",
              "ecs:Submit*",
              "ecs:StartTask",
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": [
                "arn:aws:logs:*:*:*"
            ]
        }
    ]
}
EOF

  depends_on = [aws_iam_role.ecs-ec2-role]
}

# ecs service role
resource "aws_iam_role" "ecs-service-role" {

  for_each = { for k, v in var.service_apps : k => v }
  name     = "${each.key}_ecs-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-service-attach" {
  for_each   = { for k, v in var.service_apps : k => v }
  role       = aws_iam_role.ecs-service-role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"

  depends_on = [aws_iam_role.ecs-service-role]
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

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "app" {
  for_each = { for k, v in var.service_apps : k => v }
  name     = each.key
}


resource "aws_ecs_task_definition" "app" {
  for_each = { for k, v in var.service_apps : k => v }

  family                   = each.key
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  memory                   = "2048"


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
    ],
    "environment": [
      {
          "name": "PROXY_DEST",
          "value": "${var.proxy_dest}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-group": "${aws_cloudwatch_log_group.app[each.key].name}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
EOT

}



data "aws_ami" "amazon-linux-2" {
  most_recent = true


  filter {
    name   = "name"
    values = ["*amazon-ecs-optimized"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}


resource "aws_launch_configuration" "asg_conf" {
  for_each             = { for k, v in var.service_apps : k => v }
  name_prefix          = "${each.key}-proxy-launch-config-"
  image_id             = data.aws_ami.amazon-linux-2.id
  instance_type        = "t3.large"
  iam_instance_profile = aws_iam_instance_profile.ecs-ec2-role[each.key].id
  lifecycle {
    create_before_destroy = true
  }

  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.cls[local.service_name].name} >> /etc/ecs/ecs.config
EOF

  depends_on = [aws_iam_instance_profile.ecs-ec2-role, aws_ecs_cluster.cls, data.aws_ami.amazon-linux-2]
}


resource "aws_autoscaling_group" "evt-proxy-asg" {
  for_each             = { for k, v in var.service_apps : k => v }
  name                 = "${each.key}-proxy-asg"
  launch_configuration = aws_launch_configuration.asg_conf[each.key].name
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = var.aws_vpc_subnets_private.*.id

  load_balancers = [var.service_apps_lb[each.key].name]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_launch_configuration.asg_conf,
  ]
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
  iam_role                = aws_iam_role.ecs-service-role[each.key].arn
  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 75


  load_balancer {
    elb_name       = var.service_apps_lb[each.key].name
    container_name = each.key
    container_port = 80
  }

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
  ]
}

resource "aws_appautoscaling_target" "ecs_target" {
  for_each = { for k, v in var.service_apps : k => v }

  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.cls[local.service_name].name}/${aws_ecs_service.app[each.key].name}"
  role_arn           = aws_iam_role.ecs-service-role[each.key].arn
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [
    aws_ecs_service.app,
    aws_iam_role.ecs-service-role,
  ]
}
