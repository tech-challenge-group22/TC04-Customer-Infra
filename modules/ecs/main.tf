/*====
Cloudwatch Log Group
======*/
resource "aws_cloudwatch_log_group" "customer" {
  name = "customer"

  tags = {
    Environment = "${var.prefix}"
    Application = "Customer"
  }
}

/*====
ECR repository to store our Docker images
======*/
resource "aws_ecr_repository" "customer_app" {
  name = "${var.repository_name}"
}

/*====
ECS cluster
======*/
resource "aws_ecs_cluster" "cluster" {
  name = "${var.prefix}-ecs-cluster"
}

/*====
ECS task definitions
======*/

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.prefix}_web"
  # "${file("${path.module}/tasks/web_task_definition.json"
  container_definitions    = templatefile("${path.module}/tasks/web_task_definition.json", {
    image           = "${aws_ecr_repository.customer_app.repository_url}"
    db_username = "${var.database_username}"
    db_password = "${var.database_password}"
    db_host    = "${var.dbhost}"
    database_name   = "${var.database_name}"
    log_group       = "${aws_cloudwatch_log_group.customer.name}"
    aws_region = "us-east-1"
  })
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${var.execution_arn_role}"
  task_role_arn            = "${var.execution_arn_role}"
}

/*====
App Load Balancer
======*/
resource "random_id" "target_group_sufix" {
  byte_length = 2
}

resource "random_string" "target_group" {
  length = 8
  special = false
}

resource "aws_alb_target_group" "alb_target_group" {
  lifecycle {
    create_before_destroy = true
    ignore_changes = ["name"]
  }

  # name     = "${var.prefix}-alb-target-group-${random_id.target_group_sufix.hex}"
  name     = "${var.prefix}-1${random_string.target_group.result}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
  target_type = "ip"

  tags = {
    Name = "customer-alb-target-group"
  }

  health_check {
   path = "/api-docs/#/"
 }
}

/* security group for ALB */
resource "aws_security_group" "web_inbound_sg" {
  name        = "${var.prefix}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-web-inbound-sg"
  }
}

resource "aws_alb" "alb_customer" {
  name            = "${var.prefix}-alb-customer"
  subnets         = var.public_subnet_ids
  security_groups = concat(var.security_groups_ids, [aws_security_group.ecs_service.id])

  tags = {
    Name        = "${var.prefix}-alb-customer"
    Environment = "${var.prefix}"
  }
}

resource "aws_alb_listener" "customer" {
  load_balancer_arn = "${aws_alb.alb_customer.arn}"
  port              = "3000"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.alb_target_group]

  default_action {
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    type             = "forward"
  }
}

/*====
ECS service
======*/

/* Security Group for ECS */
resource "aws_security_group" "ecs_service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.prefix}-ecs-service-sg"
  description = "Allow egress from container"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.prefix}-ecs-service-sg"
    Environment = "${var.prefix}"
  }
}

/* Simply specify the family to find the latest ACTIVE revision in that family */
data "aws_ecs_task_definition" "web" {
  task_definition = "${aws_ecs_task_definition.web.family}"
  depends_on = [ aws_ecs_task_definition.web ]
}

resource "aws_ecs_service" "web" {
  name            = "${var.prefix}-web"
  task_definition = "${aws_ecs_task_definition.web.family}:${max("${aws_ecs_task_definition.web.revision}", "${data.aws_ecs_task_definition.web.revision}")}"
  desired_count   = 2
  launch_type     = "FARGATE"
  cluster =       "${aws_ecs_cluster.cluster.id}"

  network_configuration {
    security_groups = concat(var.security_groups_ids, [aws_security_group.ecs_service.id])
    subnets         = var.subnets_ids
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    container_name   = "ms-customer"
    container_port   = "3000"
  }

  depends_on = [aws_alb_target_group.alb_target_group]
}


/*====
Auto Scaling for ECS
======*/

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  # role_arn           = "${aws_iam_role.ecs_autoscale_role.arn}"
  role_arn           = "${var.execution_arn_role}"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "up" {
  name                    = "${var.prefix}_scale_up"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension      = "ecs:service:DesiredCount"


  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = 1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

resource "aws_appautoscaling_policy" "down" {
  name                    = "${var.prefix}_scale_down"
  service_namespace       = "ecs"
  resource_id             = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension      = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = -1
    }
  }

  depends_on = [aws_appautoscaling_target.target]
}

/* metric used for auto scale */
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.prefix}_customer_web_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions = {
    ClusterName = "${aws_ecs_cluster.cluster.name}"
    ServiceName = "${aws_ecs_service.web.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.up.arn}"]
  ok_actions    = ["${aws_appautoscaling_policy.down.arn}"]
}