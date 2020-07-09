resource "aws_vpc" "main" {
    cidr_block       = "10.10.0.0/26"
    instance_tenancy = "default"

    tags = {
        name = "ig_vpc"
    }
}

resource "aws_internet_gateway" "main" {
    depends_on = [aws_vpc.main]
    
    vpc_id = aws_vpc.main.id
    tags = {
        name = "main"
    }
}

resource "aws_route_table" "main" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }
}

resource "aws_route_table_association" "main" {
    subnet_id      = aws_subnet.main.id
    route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "sec" {
    subnet_id      = aws_subnet.sec.id
    route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "jump" {
    subnet_id      = aws_subnet.jump.id
    route_table_id = aws_route_table.main.id
}

resource "aws_subnet" "main" {
    vpc_id      = aws_vpc.main.id
    cidr_block  = "10.10.0.0/28"
    availability_zone = "${var.region}b"

    tags = {
        Name = "ig_sub_main"
    }
}

resource "aws_subnet" "sec" {
    vpc_id            = aws_vpc.main.id
    cidr_block        = "10.10.0.16/28"
    availability_zone = "${var.region}a"

    tags = {
        Name = "ig_sub_sec"
    }
}

resource "aws_subnet" "jump" {
    vpc_id            = aws_vpc.main.id
    cidr_block        = "10.10.0.32/28"
    availability_zone = "${var.region}a"

    tags = {
        Name = "ig_sub_jump"
    }
}

resource "aws_security_group" "main" {
    name    = "ig_main"
    vpc_id  = aws_vpc.main.id

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["${aws_vpc.main.cidr_block}"]
    }
    ingress {
        from_port = 80
        to_port   = 80
        protocol  = "tcp"
        security_groups = ["${aws_security_group.lb-sg.id}"]
    }
    ingress {
        from_port = 22
        to_port   = 22
        protocol  = "tcp"
        security_groups = ["${aws_security_group.ssh.id}"]
    }
    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "ig_main"
    }
}

 resource "aws_security_group" "ssh" {
    name    = "ig_ssh"
    vpc_id  = aws_vpc.main.id

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = [aws_vpc.main.cidr_block]
    }
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
   }

    tags = {
        Name = "ig_ssh"
    }

    depends_on = []
}
