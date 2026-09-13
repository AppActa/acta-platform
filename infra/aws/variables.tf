# região dos recursos (obrigatório)
variable "aws_region" {
  description = "Região AWS onde a infraestrutura do ACTA será criada."
  type        = string

  validation {
    # apenas valida formato
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region deve ser uma região AWS válida, por exemplo sa-east-1."
  }
}

# nome de ssh cadstrada na aws (obrigatório)
variable "key_name" {
  description = "Nome de um EC2 Key Pair já existente na região escolhida."
  type        = string

  validation {
    condition     = length(trimspace(var.key_name)) > 0
    error_message = "key_name não pode ser vazio."
  }
}

# ip admin (obrigatório)
# ssh na porta 22
# api o k8s na porta 6443
variable "admin_cidr" {
  description = "IP público autorizado a acessar SSH e a API do K3s, obrigatoriamente em /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/32$", var.admin_cidr))
    error_message = "admin_cidr deve ser um IPv4 válido com prefixo /32."
  }
}

# capacidade da vm (obrigatório)
variable "instance_type" {
  description = "Tipo da instância EC2 x86_64 que executará o K3s."
  type        = string

  validation {
    condition     = length(trimspace(var.instance_type)) > 0
    error_message = "instance_type não pode ser vazio."
  }
}

# espaço total de endereços da vpc
variable "vpc_cidr" {
  description = "CIDR privado da VPC."
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr deve ser um bloco CIDR válido."
  }
}

# separa parte da vpc para a subnet pública
# onde fica a ec2
variable "public_subnet_cidr" {
  description = "CIDR da subnet pública. Deve estar contido em vpc_cidr."
  type        = string
  default     = "10.50.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr deve ser um bloco CIDR válido."
  }
}

# tamanho do disco principal da ec2 (em gib)
# onde fica ubuntu, k3s, imagens, logs, dados internos...
variable "root_volume_size" {
  description = "Tamanho, em GiB, do volume raiz GP3 criptografado."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 16384
    error_message = "root_volume_size deve estar entre 20 e 16384 GiB."
  }
}
