######################################
# ECS Cluster Configuration
######################################
resource "aws_ecs_cluster" "cluster" {
  name = "${local.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.prefix}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
}

######################################
# ECS Task Roles Configuration
######################################
resource "aws_iam_role" "task_exec" {

  name               = "${local.prefix}-task-exec-role"
  assume_role_policy = file("${path.module}/iam_policy_document/assume_ecs_task.json")

  tags = {
    Name = "${local.prefix}-task-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

######################################
# CloudWatch Logs Configuration
######################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${local.prefix}-service"
  retention_in_days = 7

  tags = {
    Name = "/aws/ecs/${local.prefix}-service"
  }
}

######################################
# Security Group Configuration
######################################
resource "aws_security_group" "ecs" {
  vpc_id      = aws_vpc.vpc.id
  name        = "${local.prefix}-ecs-sg"
  description = "${local.prefix}-ecs-sg"

  tags = {
    Name = "${local.prefix}-ecs-sg"
  }
}

resource "aws_security_group_rule" "ecs_egress_all" {
  security_group_id = aws_security_group.ecs.id
  type              = "egress"
  description       = "All Connection"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_ecs" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 80
  to_port                  = 80
  source_security_group_id = aws_security_group.ecs.id
  description              = "Web Container"
}

resource "aws_security_group_rule" "ecs_ingress_alb" {
  security_group_id        = aws_security_group_rule.alb_egress_ecs.source_security_group_id
  type                     = "ingress"
  protocol                 = aws_security_group_rule.alb_egress_ecs.protocol
  from_port                = aws_security_group_rule.alb_egress_ecs.from_port
  to_port                  = aws_security_group_rule.alb_egress_ecs.to_port
  source_security_group_id = aws_security_group_rule.alb_egress_ecs.security_group_id
  description              = "Application Load Balancer"
}

######################################
# Target Group Configuration
######################################
resource "aws_lb_target_group" "blue" {
  name            = "${local.prefix}-blue-tg"
  target_type     = "ip"
  vpc_id          = aws_vpc.vpc.id
  protocol        = "HTTP"
  port            = 80
  ip_address_type = "ipv4"

  health_check {
    enabled             = true
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 0 # for testing
}

resource "aws_lb_listener_rule" "alb_80_web" {
  listener_arn = aws_lb_listener.alb_80.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }

  lifecycle {
    ignore_changes = [
      action
    ]
  }
}

resource "aws_lb_target_group" "green" {
  name            = "${local.prefix}-green-tg"
  target_type     = "ip"
  vpc_id          = aws_vpc.vpc.id
  protocol        = "HTTP"
  port            = 80
  ip_address_type = "ipv4"

  health_check {
    enabled             = true
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 0 # for testing
}

resource "aws_lb_listener_rule" "alb_8080_web" {
  listener_arn = aws_lb_listener.alb_8080.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }

  lifecycle {
    ignore_changes = [
      action
    ]
  }
}

######################################
# Task Definition Configuration
######################################
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.prefix}-td"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.task_exec.arn

  memory = 512
  cpu    = 256

  container_definitions = templatefile("${path.module}/task_definition/web.json", {
    region = data.aws_region.current.name

    web_image_url     = "${aws_ecr_repository.web.repository_url}:first"
    log_group_name    = aws_cloudwatch_log_group.ecs.name
    log_stream_prefix = "ecs"
  })

  lifecycle {
    ignore_changes = [
      container_definitions
    ]
  }
}

######################################
# ECS Service Configuration
######################################
resource "aws_ecs_service" "service" {
  name            = "${local.prefix}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.ecs.id]
    subnets = [
      aws_subnet.private_a.id,
      aws_subnet.private_c.id
    ]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "web"
    container_port   = 80
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  tags = {
    Name = "${local.prefix}-service"
  }

  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition,
      load_balancer
    ]
  }
}