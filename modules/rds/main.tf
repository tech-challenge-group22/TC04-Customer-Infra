/*====
RDS
======*/

/* subnet used by rds */
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "${var.prefix}-rds-subnet-group"
  description = "RDS subnet group"
  subnet_ids  = var.subnet_ids
  tags = {
    Environment = "${var.prefix}"
  }
}

/* Security Group for resources that want to access the Database */
resource "aws_security_group" "db_access_sg" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.prefix}-db-access-sg"
  description = "Allow access to RDS"

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

  tags = {
    Name        = "${var.prefix}-db-access-sg"
    Environment = "${var.prefix}"
  }
}

resource "aws_security_group" "rds_sg" {
  name = "${var.prefix}-rds-sg"
  description = "${var.prefix} Security Group"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name = "${var.prefix}-rds-sg"
    Environment =  "${var.prefix}"
  }

  // allows traffic from the SG itself
  ingress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      self = true
  }

  //allow traffic for TCP 5432
  ingress {
      from_port = 3306
      to_port   = 3306
      protocol  = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      security_groups = ["${aws_security_group.db_access_sg.id}"]
  }

  // outbound internet access
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds" {
  identifier             = "${var.prefix}-database"
  allocated_storage      = "${var.allocated_storage}"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "${var.instance_class}"
  multi_az               = "${var.multi_az}"
  db_name                   = "${var.database_name}"
  username               = "${var.database_username}"
  password               = "${var.database_password}"
  db_subnet_group_name   = "${aws_db_subnet_group.rds_subnet_group.id}"
  vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
  skip_final_snapshot    = true
  publicly_accessible = true
  #snapshot_identifier    = "rds-${var.prefix}-snapshot"
  tags = {
    Environment = "${var.prefix}"
  }
}

resource "null_resource" "customer_setup_db" {
  depends_on = [aws_db_instance.rds] #wait for the db to be ready
  triggers = {
    instance_id = aws_db_instance.rds.id
  }

  provisioner "local-exec" {
      command = "mysql -u${var.database_username} -p${var.database_password} -h${aws_db_instance.rds.address} -P3306 < modules/rds/script-rds.sql"
   }

}
