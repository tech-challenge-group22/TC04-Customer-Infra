
provider "aws" {
 region = "us-east-1"
}

# terraform {
#   backend "s3" {
#     bucket         = "tfstate-tcfiap-group22"
#     key            = "terraform.tfstate"
#     region         = "us-east-1"
#   }
# }

resource "aws_vpc" "aws_postech_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "aws_gateway_vpc" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  tags = {
    Name = "aws-gateway-vpc"
  }
}

resource "aws_route_table" "aws_route_postech" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aws_gateway_vpc.id
  }
  tags = {
    Name = "aws_route_postech"
  }
}
resource "aws_subnet" "public_subnet_a" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table_association" "aws_subnet_association" {
  subnet_id     = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.aws_route_postech.id
}

resource "aws_route_table_association" "aws_subnet_association_b" {
  subnet_id     = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.aws_route_postech.id
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_security_group" "aws_inbound_security_group" {
  name        = "aws_inbound_security_group"
  description = "Security Group"
  vpc_id = aws_vpc.aws_postech_vpc.id

  // Regra para HTTP
  ingress {
    from_port   = 0
    to_port     = 8080
    protocol    = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }


}

resource "aws_security_group" "database_security_group" {
  name = "database secutiry group"
  description = "enable mysql/aurora"
  vpc_id = aws_vpc.aws_postech_vpc.id
   ingress {
    description = "mysql/aurora access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.aws_inbound_security_group.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name ="database security group"
  }
}

resource "aws_db_instance" "db_postech_rds" {
  allocated_storage = 10
  engine = "mysql"
  engine_version = "5.7"
  instance_class = "db.t2.micro"
  publicly_accessible = true
  identifier = "aws-rds-postech"
  username = var.db_username
  password =  var.db_password
  skip_final_snapshot = true
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  db_name = "DeliverySystem"
  
}

resource "aws_db_subnet_group" "db_subnet" {
    name = "dbsubnet"
    subnet_ids = [ aws_subnet.public_subnet_a.id , aws_subnet.public_subnet_b.id ]
  
}

resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.db_postech_rds] #wait for the db to be ready
  triggers = {
    instance_id = aws_db_instance.db_postech_rds.id
  }

  provisioner "local-exec" {
      command = "mysql -u${aws_db_instance.db_postech_rds.username} -p${aws_db_instance.db_postech_rds.password} -h${aws_db_instance.db_postech_rds.address} -P${aws_db_instance.db_postech_rds.port} < script-rds.sql"
   }
}


## --------- APPLICATION --------- ##

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.aws_postech_vpc.id
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      prefix_list_ids = []
  }
  tags = {
      Name = "${var.prefix}-sg"
  }
}

resource "aws_iam_role" "cluster" {
  name = "${var.prefix}-${var.cluster_name}-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}    
POLICY
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSVPCResourceController" {
  role = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSClusterPolicy" {
  role = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "log" {
  name = "/aws/eks-terraform-course/${var.prefix}-${var.cluster_name}/cluster"
  retention_in_days = var.retention_days
}

resource "aws_eks_cluster" "cluster" {
  name = "${var.prefix}-${var.cluster_name}"
  role_arn = aws_iam_role.cluster.arn
  enabled_cluster_log_types = ["api","audit"]
  vpc_config {
      subnet_ids = [ aws_subnet.public_subnet_a.id , aws_subnet.public_subnet_b.id ]
      security_group_ids = [aws_security_group.sg.id]
  }
  depends_on = [
    aws_cloudwatch_log_group.log,
    aws_iam_role_policy_attachment.cluster-AmazonEKSVPCResourceController,
    aws_iam_role_policy_attachment.cluster-AmazonEKSClusterPolicy,
  ]
}

resource "aws_iam_role" "node" {
  name = "${var.prefix}-${var.cluster_name}-role-node"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_eks_node_group" "node-1" {
  cluster_name = aws_eks_cluster.cluster.name
  node_group_name = "node-1"
  node_role_arn = aws_iam_role.node.arn
  subnet_ids = [ aws_subnet.public_subnet_a.id , aws_subnet.public_subnet_b.id ]
  instance_types = ["t3.micro"]
  scaling_config {
    desired_size = var.desired_size
    max_size = var.max_size
    min_size = var.min_size
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.node-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node-AmazonEC2ContainerRegistryReadOnly,
  ]
}
