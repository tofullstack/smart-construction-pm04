output "app_public_ip" {
  value = aws_eip.app.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "db_public_ip" {
  description = "Usado apenas para SSH temporário da pipeline e saída para a internet (apt/docker pull)"
  value       = aws_instance.db.public_ip
}

output "db_private_ip" {
  value = aws_instance.db.private_ip
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "app_data_volume_id" {
  value = aws_ebs_volume.app_data.id
}

output "db_data_volume_id" {
  value = aws_ebs_volume.db_data.id
}

output "backup_bucket" {
  value = aws_s3_bucket.backup.bucket
}
