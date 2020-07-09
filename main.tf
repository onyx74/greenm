provider "aws" {
    region  = var.region
    version = "~> 2.69"
}

resource "tls_private_key" "appkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "appkey" {
  key_name   = var.key_name
  public_key = tls_private_key.appkey.public_key_openssh
}

resource "null_resource" "appkey" {
  provisioner "local-exec" {
    command = "echo ${tls_private_key.appkey.private_key_pem} > appkey.pem"
  }
}

resource "aws_instance" "jump_host" {
    ami                         = var.jump_host_ami
    instance_type               = var.instance_type
    key_name                    = aws_key_pair.appkey.key_name
    subnet_id                   = aws_subnet.jump.id
    security_groups             = ["${aws_security_group.ssh.id}"]
    associate_public_ip_address = true

    tags = {
        Name = "jumphost"
    }
 }

resource "aws_launch_configuration" "app" {
    depends_on                  = [aws_security_group.main]

    name_prefix                  = "pet-service"
    image_id                    = var.instance_ami
    instance_type               = var.instance_type
    key_name                    = aws_key_pair.appkey.key_name
    security_groups             = ["${aws_security_group.main.id}"]
    associate_public_ip_address = true

    user_data = <<-EOF
        #! /bin/bash
        yum install -y epel-release 
        yum install -y nginx git java-1.8.0-openjdk-devel
        echo events { } > /etc/nginx/nginx.conf
        echo http{ >> /etc/nginx/nginx.conf
        echo server{ >> /etc/nginx/nginx.conf
        echo listen     *:80\; >> /etc/nginx/nginx.conf
        echo server_name www.proxy.com\; >> /etc/nginx/nginx.conf
        echo # allow large uploads of files\; >> /etc/nginx/nginx.conf
        echo client_max_body_size 1G\; >> /etc/nginx/nginx.conf
        echo location / { >> /etc/nginx/nginx.conf
        echo proxy_pass http://127.0.0.1:8080/\; >> /etc/nginx/nginx.conf
        echo proxy_set_header Host \$host\; >> /etc/nginx/nginx.conf
        echo proxy_set_header X-Real-IP \$remote_addr\; >> /etc/nginx/nginx.conf
        echo proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for\; >> /etc/nginx/nginx.conf
        echo }}} >> /etc/nginx/nginx.conf
        git clone https://github.com/spring-projects/spring-petclinic.git  /root/spring-petclinic
        cd /root/spring-petclinic
        systemctl enable nginx
        systemctl start nginx
        ./mvnw package
        java -jar target/*.jar 
    EOF

}

resource "aws_autoscaling_group" "petclinic_group" {
    name                        = "petclinic"
    max_size                    = 5
    min_size                    = 1
    health_check_grace_period   = 300
    health_check_type           = "ELB"
    desired_capacity            = 1
    force_delete                = true
    launch_configuration         = aws_launch_configuration.app.name
    vpc_zone_identifier          = ["${aws_subnet.main.id}","${aws_subnet.sec.id}"]
    # load_balancers              = ["${aws_elb.elb.name}"]
    target_group_arns           = [aws_alb_target_group.alb_target_group.arn]

    tag {
        key                 = "Name"
        value               = "pet-service"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_policy" "pet-up" {
    name                        = "scale-up"
    autoscaling_group_name      = aws_autoscaling_group.petclinic_group.name
    adjustment_type             = "ChangeInCapacity"
    scaling_adjustment          = "1"
    cooldown                    = "300"
    policy_type                 = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "cw-up" {
    alarm_name                  = "cw-up"
    comparison_operator         = "GreaterThanOrEqualToThreshold"
    evaluation_periods          = "2"
    metric_name                 = "CPUUtilization"
    namespace                   = "AWS/EC2"
    period                      = "120"
    statistic                   = "Average"
    threshold                   = "80"

    dimensions = {
        "AutoScalingGroupName" = aws_autoscaling_group.petclinic_group.name
    }

    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.pet-up.arn}"]

}

resource "aws_autoscaling_policy" "pet-down" {
    name                        = "scale-down"
    autoscaling_group_name      = aws_autoscaling_group.petclinic_group.name
    adjustment_type             = "ChangeInCapacity"
    scaling_adjustment          = "-1"
    cooldown                    = "300"
    policy_type                 = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "cw-down" {
    alarm_name                  = "cw-down"
    comparison_operator         = "LessThanOrEqualToThreshold"
    evaluation_periods          = "2"
    metric_name                 = "CPUUtilization"
    namespace                   = "AWS/EC2"
    period                      = "240"
    statistic                   = "Average"
    threshold                   = "20"

    dimensions = {
        "AutoScalingGroupName" = aws_autoscaling_group.petclinic_group.name
    }

    actions_enabled = true
    alarm_actions   = ["${aws_autoscaling_policy.pet-down.arn}"]

}

resource "aws_security_group" "lb-sg" {
    name    = "ig_allow_http"
    vpc_id  = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port   = 80
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        name = "lb-sg"
    }
}

resource "aws_alb" "alb" {
  name              = var.alb_name
#   subnets         = ["${split(",",var.alb_subnets)}"]
  subnets           = ["${aws_subnet.main.id}","${aws_subnet.sec.id}"]
  security_groups   = ["${aws_security_group.lb-sg.id}"]
  internal          = false
  idle_timeout      = 60
  tags = {
    Name    = "${var.alb_name}"
  }
}

resource "aws_alb_target_group" "alb_target_group" {
  name     = var.target_group_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  tags = {
    name = var.target_group_name
  }
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    path                = "/"
    port                = 80
  }
}

resource "aws_alb_listener" "alb_listener" {
  depends_on        = [aws_alb_target_group.alb_target_group]

  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    type             = "forward"
  }
}
