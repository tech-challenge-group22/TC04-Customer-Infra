output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

output "public_subnets_id" {
  value = [for subnet in aws_subnet.public_subnet : subnet.id]
}

output "private_subnets_id" {
  value = [for subnet in aws_subnet.private_subnet : subnet.id]
}

output "default_sg_id" {
  value = "${aws_security_group.default.id}"
}

output "security_groups_ids" {
  value = aws_security_group.default.id
}

