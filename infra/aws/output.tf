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
