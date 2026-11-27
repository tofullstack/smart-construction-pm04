variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Ambiente de destino (dev, homolog, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "environment deve ser dev, homolog ou prod."
  }
}

variable "instance_name" {
  description = "Nome (tag Name) da VM da aplicação"
  type        = string
  default     = "vm-smart-app"
}

variable "app_instance_type" {
  description = "Tipo da VM da aplicação (Nginx, Next.js, API, SeaweedFS)"
  type        = string
  default     = "t3.small"
}

variable "db_instance_type" {
  description = "Tipo da VM exclusiva do PostgreSQL"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "Chave pública usada pelo Ansible (vem do secret SSH_PUBLIC_KEY)"
  type        = string
}

variable "state_bucket" {
  description = "Bucket do Terraform state; o prefixo certs/ guarda o cache do certificado HTTPS"
  type        = string
}

variable "vpc_cidr" {
  description = "Faixa da rede privada"
  type        = string
  default     = "10.20.0.0/16"
}

variable "app_data_size" {
  description = "Tamanho (GB) do disco de dados da VM da aplicação (imagens/SeaweedFS)"
  type        = number
  default     = 25
}

variable "db_data_size" {
  description = "Tamanho (GB) do disco de dados do PostgreSQL"
  type        = number
  default     = 25
}
