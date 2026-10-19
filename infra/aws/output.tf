# mostra o elastic ip da ec2
output "public_ip" {
  description = "Elastic IP público do servidor K3s."
  value       = aws_eip.k3s.public_ip
}

# id da ec2 criado pela aws
output "instance_id" {
  description = "ID da instância EC2 do servidor K3s."
  value       = aws_instance.k3s.id
}

# qual zona de região foi criada na ec2
output "availability_zone" {
  description = "Zona de disponibilidade usada pela instância."
  value       = aws_instance.k3s.availability_zone
}

# modelo de comando ssh usando o elastic ip
output "ssh_command" {
  description = "Modelo de comando para acessar a instância usando a chave privada correspondente."
  value       = "ssh -i <caminho-da-chave-privada> ubuntu@${aws_eip.k3s.public_ip}"
}

output "api_urls" {
  description = "URLs HTTPS publicadas pelo Traefik."
  value = {
    ai         = "https://acta-ai.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    auth_api   = "https://acta-auth-api.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    pg_api     = "https://acta-pg-api.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    mongo_api  = "https://acta-mongo-api.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    import_api = "https://acta-import-api.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    fcm_api    = "https://acta-fcm-api.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io"
    mcp        = "https://acta-mcp.${replace(aws_eip.k3s.public_ip, ".", "-")}.sslip.io/mcp"
  }
}