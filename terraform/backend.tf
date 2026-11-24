# O bucket e a chave (um state por ambiente) são passados pela pipeline:
#   terraform init -backend-config="bucket=..." -backend-config="key=smart-construction/<env>.tfstate"
terraform {
  backend "s3" {
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # trava nativa no S3 (Terraform >= 1.10), sem DynamoDB
  }
}
