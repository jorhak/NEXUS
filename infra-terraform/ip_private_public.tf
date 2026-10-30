# =============================================================================
# IPs de la Instancia Pública
# =============================================================================
output "instancia_publica_ip_publica" {
  value       = aws_instance.instancia_publica.public_ip
  description = "Dirección IP pública para conectarte desde el exterior (Internet)"
}

output "instancia_publica_ip_privada" {
  value       = aws_instance.instancia_publica.private_ip
  description = "Dirección IP interna de la instancia pública"
}
# =============================================================================
# IPs de las Instancias Privadas
# =============================================================================
output "instancia_privada_uno_ip_privada" {
  value       = aws_instance.instancia_privada.private_ip
  description = "Dirección IP interna de la primera máquina privada"
}

output "instancia_privada_dos_ip_privada" {
  value       = aws_instance.instancia_privada_dos.private_ip
  description = "Dirección IP interna de la segunda máquina privada"
}
