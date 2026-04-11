resource "aws_lb" "alb" {
  name               = "k8s-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "tg" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_target_group_attachment" "targets" {
  count            = length(var.targets)
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = var.targets[count.index]
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

variable "vpc_id" {
  type = string
}

variable "sg_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "targets" {
    type = list(string)
}

output "alb_dns" {
  value = aws_lb.alb.dns_name
}
