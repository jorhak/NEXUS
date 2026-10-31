# CREAMOS NUESTRA VPC 
resource "aws_vpc" "nexus" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "nexus-vpc"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# CREAMOS LAS SUBNETS PUBLIC Y PRIVATE 
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.nexus.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  map_public_ip_on_launch = true 

  tags = {
    Name = "nexus-subnet-public"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.nexus.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2a"


  tags = {
    Name = "nexus-subnet-private"
    ENV  = "DEV"
    USER = "SNOW"
  }
}


# CREAMOS IGW PARA TENER SALIDA A INTERNET 
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.nexus.id

  tags = {
    Name = "gw-nexus"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# CREAR ROUTE TABLE PARA DIRIGIR NUESTRO TRAFICO 
resource "aws_route_table" "tabla_rutas" {
  vpc_id = aws_vpc.nexus.id

  tags = {
    Name = "nexus-rt-public"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# CREAR ROUTE TABLE PARA LA ZONA PRIVADA
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.nexus.id

  # Envía todo el tráfico de internet hacia la instancia pública
  route {
    cidr_block  = "0.0.0.0/0"
    network_interface_id = aws_instance.instancia_publica.primary_network_interface_id 
  }

  tags = {
    Name = "nexus-rt-private"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# AGREGAR RUTAS IGW, SUBNET PUBLIC, SUBNET PRIVATE 
# IGW
resource "aws_route" "ruta_igw" {
  route_table_id         = aws_route_table.tabla_rutas.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id 
}

# SUBNET PUBLIC
resource "aws_route_table_association" "ruta_subnet_public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.tabla_rutas.id
}

# SUBNET PRIVATE
#resource "aws_route_table_association" "ruta_subnet_private" {
#  subnet_id      = aws_subnet.private_subnet.id
#  route_table_id = aws_route_table.tabla_rutas.id
#}
# 
resource "aws_route_table_association" "ruta_subnet_private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# CREAMOS SECURITY GROUP 
resource "aws_security_group" "permisos" {
  name        = "nexus-security-group"
  description = "Security Gruop para mis instancias publicas y privadas"
  vpc_id      = aws_vpc.nexus.id

  tags = {
    Name = "nexus-sg"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

resource "aws_vpc_security_group_ingress_rule" "comunicacion_interna" {
  security_group_id = aws_security_group.permisos.id

  # Al usar 'referenced_security_group_id', cualquier instancia que 
  # tenga asignado este mismo SG podrá hablarle a las demás.
  referenced_security_group_id = aws_security_group.permisos.id
  
  ip_protocol = "-1" # Permite todos los protocolos y todos los puertos internamente
}

resource "aws_vpc_security_group_egress_rule" "salida_libre" {
  security_group_id = aws_security_group.permisos.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# HABILITAR PUERTOS
resource "aws_vpc_security_group_ingress_rule" "acceso_ssh" {
  security_group_id = aws_security_group.permisos.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22

  tags = {
    Name = "nexus-egress-ssh"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

resource "aws_vpc_security_group_ingress_rule" "acceso_rdp" {
  security_group_id = aws_security_group.permisos.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 3389
  ip_protocol = "tcp"
  to_port     = 3389

  tags = {
    Name = "nexus-egress-rdp"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# CREAR INSTANCIAS 
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# INSTANCIA PUBLICA 
resource "aws_instance" "instancia_publica" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m7i-flex.large"
  subnet_id              = aws_subnet.public_subnet.id 
  vpc_security_group_ids = [aws_security_group.permisos.id]
  key_name               = aws_key_pair.mi_llave_privada.key_name 
  
  # REQUISITO 1: Permitir que reenvíe paquetes de otras IPs
  source_dest_check = false 

  # REQUISITO 2: Script para habilitar NAT masquerading en Linux
  user_data = <<-EOF
              #!/bin/bash
              # Cambiar hostname
              hostnamectl set-hostname servidor-publico
              echo "127.0.0.1 servidor-publico" >> /etc/hosts

              # Forzar el modo no interactivo para TODO el script
              export DEBIAN_FRONTEND=noninteractive

              # 1. ESPERAR A QUE EL GESTOR DE PAQUETES SE LIBERE
              echo "Esperando a que finalicen las actualizaciones automáticas de Ubuntu..."
              while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
                sleep 5
              done

              # Habilitar el reenvío de paquetes IP a nivel de Kernel
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
              sysctl -p

              # Configurar iptables para enmascarar el tráfico de la VPC
              IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
              iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
              
              # Preconfigurar respuestas automáticas correctas para iptables-persistent
              echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
              echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

              # Actualizar e instalar herramientas de red de manera 100% silenciosa
              apt-get update
              apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" iptables-persistent
              
              # Permitir acceso por RDP y resolver permisos de certificados TLS
              apt-get install -y xrdp 
              systemctl enable --now xrdp
              adduser xrdp ssl-cert  # Previene desconexiones inmediatas en xrdp

              # Ajustar optimizaciones en xrdp.ini para evitar errores de fastpath/bitmap de clientes Windows
              sed -i 's/use_fastpath=both/use_fastpath=none/g' /etc/xrdp/xrdp.ini
              sed -i 's/bitmap_cache=yes/bitmap_cache=no/g' /etc/xrdp/xrdp.ini
              sed -i 's/new_cursors=true/new_cursors=false/g' /etc/xrdp/xrdp.ini
              systemctl restart xrdp
              
              # Instalar entorno gráfico (tardará de 10 a 15 minutos en t3.micro)
              apt-get install -y xfce4 xfce4-goodies
              echo "xfce4-session" > ~/.xsession
              chmod +x ~/.xsession

              # Colocar la hora de Bolivia
              timedatectl set-timezone America/La_Paz
              # Instalar navegador
              apt-get install -y chromium-browser
              # Instalar ansible
              apt-get install -y ansible
              EOF

  tags = {
    Name = "nexus-instancia-public"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

# INSTANCIAS PRIVADAS 
resource "aws_instance" "instancia_privada" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "c7i-flex.large"
  subnet_id              = aws_subnet.private_subnet.id 
  vpc_security_group_ids = [aws_security_group.permisos.id]
  key_name               = aws_key_pair.mi_llave_privada.key_name 
  user_data = <<-EOF
              #!/bin/bash
              # Cambiar hostname
              hostnamectl set-hostname servidor-nexus
              echo "127.0.0.1 servidor-nexus" >> /etc/hosts
              # Colocar la hora de Bolivia
              timedatectl set-timezone America/La_Paz
              EOF
  tags = {
    Name = "nexus-instancia-private"
    ENV  = "DEV"
    USER = "SNOW"
  }
}

resource "aws_instance" "instancia_privada_dos" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "c7i-flex.large"
  subnet_id              = aws_subnet.private_subnet.id 
  vpc_security_group_ids = [aws_security_group.permisos.id]
  key_name               = aws_key_pair.mi_llave_privada.key_name 
  user_data = <<-EOF
              #!/bin/bash
              # Cambiar hostname
              hostnamectl set-hostname servidor-cliente
              echo "127.0.0.1 servidor-cliente" >> /etc/hosts
              # Colocar la hora de Bolivia
              timedatectl set-timezone America/La_Paz
              EOF
  tags = {
    Name = "nexus-instancia-private"
    ENV  = "DEV"
    USER = "SNOW"
  }
}




