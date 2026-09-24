# configuração do terraform
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# configuração da AWS
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ACTA"
      ManagedBy = "Terraform"
    }
  }
}

# verificação de disponibilidade da região escolhida
data "aws_availability_zones" "available" {
  state = "available"
}

# pull da imagem ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # conta oficial da canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# rede privada do acta (vpc)
resource "aws_vpc" "acta" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "acta-prod-vpc"
  }
}

# porta da vpc com a internet
resource "aws_internet_gateway" "acta" {
  vpc_id = aws_vpc.acta.id

  tags = {
    Name = "acta-prod-igw"
  }
}

# subnet na vpc 
# onde a ec2 do k3s vai ficar
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.acta.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "acta-prod-public"
  }
}

# tabela de rotas
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.acta.id

  route {
    cidr_block = "0.0.0.0/0" # qualquer ipv4
    gateway_id = aws_internet_gateway.acta.id
  }

  tags = {
    Name = "acta-prod-public"
  }
}

# rotas na subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# firewall da ec2
resource "aws_security_group" "k3s" {
  name        = "acta-prod-k3s"
  description = "Acesso restrito ao k3s"
  vpc_id      = aws_vpc.acta.id

  # libera porta 22
  ingress {
    description = "SSH administrativo"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr] # apenas para esse ip
  }

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS publico"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # libera api do kubernetes
  ingress {
    description = "API Kubernetes"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # permite conexão de ec2 para qualquer endereço
  egress {
    description = "Saida necessaria para atualizacoes e imagens"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # todos os protocolos
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "acta-prod-k3s"
  }
}

# criação da máquina virtual  
resource "aws_instance" "k3s" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = aws_subnet.public.id

  # instância pública da subnet
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true

  # acesso a dados internos da ec2 exigindo token de segurança
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true # evita discos abertos depois da exclusão
  }

  # define bash como interpretador
  # para script se houver erro
  # usa ip público fixo, somente o proprietário lê ou altera o kubeconfig
  user_data_replace_on_change = true
  user_data                   = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    curl --proto '=https' --tlsv1.2 -sfL https://get.k3s.io \
      | INSTALL_K3S_EXEC="server --secrets-encryption --tls-san=${aws_eip.k3s.public_ip} --write-kubeconfig-mode=600" sh -
  EOT

  # só criada depois da subnet na tabela de rotas
  depends_on = [aws_route_table_association.public]

  tags = {
    Name = "acta-prod-k3s"
  }
}

# elastic ip
# reserva ipv4 fixo (não muda quando pausa ou é reinicializado)
resource "aws_eip" "k3s" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.acta]

  tags = {
    Name = "acta-prod-k3s"
  }
}

# elastic ip com a ec2
resource "aws_eip_association" "k3s" {
  allocation_id = aws_eip.k3s.id
  instance_id   = aws_instance.k3s.id
}