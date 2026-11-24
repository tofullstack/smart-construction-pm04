locals {
  name = "smart-${var.environment}"
}

data "aws_caller_identity" "me" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Ubuntu 24.04 LTS oficial da Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------------------------------------------------------------- rede
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 10.20.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-subnet" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.name}-rt" }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ---------------------------------------------------------------- security groups
# Regras como recursos separados: a regra temporária de SSH criada pela
# pipeline (para o IP do runner) não é vista como "drift" pelo Terraform.
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "VM da aplicacao: somente HTTP/HTTPS publicos"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "VM do banco: 5432 somente a partir da VM da aplicacao"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP (redireciona para HTTPS e valida Let's Encrypt)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS publico"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL somente da VM da aplicacao"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "db_all" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------- IAM (backup no S3)
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vm" {
  name               = "${local.name}-vm-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "vm_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backup.arn, "arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "${aws_s3_bucket.backup.arn}/*",
      "arn:aws:s3:::${var.state_bucket}/certs/${var.environment}/*",
    ]
  }
}

resource "aws_iam_role_policy" "vm_s3" {
  name   = "${local.name}-vm-s3"
  role   = aws_iam_role.vm.id
  policy = data.aws_iam_policy_document.vm_s3.json
}

resource "aws_iam_instance_profile" "vm" {
  name = "${local.name}-vm-profile"
  role = aws_iam_role.vm.name
}

# ---------------------------------------------------------------- VMs
resource "aws_key_pair" "ci" {
  key_name   = "${local.name}-ci"
  public_key = var.ssh_public_key
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.ci.key_name
  iam_instance_profile   = aws_iam_instance_profile.vm.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = var.instance_name, Role = "app" }

  lifecycle {
    ignore_changes = [ami] # AMI nova não recria a VM; atualização do SO é feita pelo Ansible
  }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.ci.key_name
  iam_instance_profile   = aws_iam_instance_profile.vm.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "${local.name}-db", Role = "db" }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Discos de dados separados: sobrevivem a reinícios, troca de tipo e até recriação da VM
resource "aws_ebs_volume" "app_data" {
  availability_zone = aws_subnet.main.availability_zone
  size              = var.app_data_size
  type              = "gp3"
  tags              = { Name = "${local.name}-app-data" }
}

resource "aws_volume_attachment" "app_data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.app_data.id
  instance_id                    = aws_instance.app.id
  stop_instance_before_detaching = true
}

resource "aws_ebs_volume" "db_data" {
  availability_zone = aws_subnet.main.availability_zone
  size              = var.db_data_size
  type              = "gp3"
  tags              = { Name = "${local.name}-db-data" }
}

resource "aws_volume_attachment" "db_data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.db_data.id
  instance_id                    = aws_instance.db.id
  stop_instance_before_detaching = true
}

# IP fixo da aplicação (o DNS do DuckDNS aponta para ele)
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id
  tags     = { Name = "${local.name}-app-eip" }
}

# ---------------------------------------------------------------- backup
resource "aws_s3_bucket" "backup" {
  bucket        = "${local.name}-backup-${data.aws_caller_identity.me.account_id}"
  force_destroy = true # permite o "encerrar" pela pipeline; baixe as evidências antes
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
