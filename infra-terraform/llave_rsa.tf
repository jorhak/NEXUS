#Creamos el par de llaves
resource "tls_private_key" "llave_privada" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#Creamos la llave en AWS
resource "aws_key_pair" "mi_llave_privada" {
  key_name   = "nexus-kp"
  public_key = tls_private_key.llave_privada.public_key_openssh
}

#Guardamos la llave privada en un fichero .pem
resource "local_file" "llave_pem" {
  content  = tls_private_key.llave_privada.private_key_pem
  filename = "${path.module}/nexus-kp.pem"
  file_permission = "0600"
}
