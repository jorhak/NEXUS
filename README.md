# Requerimiento
Como ya se cuenta con paquetes .deb personalizado, se nos solicito la \
implementacion de un repositorio privado, para uso interno para los diferentes \
ambientes **DEV,QA,PROD**.
# Arquitectura
Se debe emplear una arquitectura en donde se tenga una VPC que va contar \
con dos Subnet's (privada y publica), esta VPC tambien va contar con dos Route \
Tables (privada y publica), se van a tener tres instancias ec2, una de las \
instanicas se va encontrar en la subnet publica y va tener la funcion de trabajar \
como una instancia nat para que las instancias que van a estar en la subnet privada \
tenga salida a internet. \
![Arquitectura](./assets/nexus.gif)

# Requisitos previos 
1. AWS CLI 
2. Terraform
3. Ansible
4. Docker
5. Remmina

# Solucion 
Para tener la infraestructura necesaria para llegar a tener un respositorio privada \
(servidor nexus), servidor cliente, servidor docker y un servidor publico que va tener \
llegada a los servidores privados, vamos a utilizar Terraform para toda la infraestructura, \
y para la instalacion de Nexus y Docker, se va utilizar Ansible que va estar instalado en \
el servidor publico. \
Para nuestro repositorio privado vamos a utilizar Nexus en su version comunitaria. \
Acontinuacion se va explicar que se va llevar a cabo en cada servidor:
1. **Servidor publico**: En este servidor se va instalar Ansible, XRDP (acceso remoto), \
   entorno grafico xfce4
2. **Servidor nexus**: Se va a instalar la aplicacion Nexus, se van a configurar usuarios, \
   repositorios, se van a crear llaves para nuestro repositorio. 
3. **Servidor publico**: Vamos a configurar al servidor para que pueda llegar a nuestro repositorio \
   privado y realizar la instalacion de los paquetes privados.
4. **Servidor docker**: Vamos a agregar como registry inseguro a nuestro repositorio que se creo \
   en Nexus.
# Desplegar infraestructura 
```
terraform plan --out main-plan.tfplan
terraform apply main-plan.tfplan
```
# Copiar nginx-custom_1.26.1_amd64.deb 
```
scp -i infra-terraform/nexus-kp.pem infra-terraform/nginx-custom_1.26.1_amd64.deb ubuntu@3.148.228.118:/home/ubuntu/
```
# Copiar llave 
```
scp -i infra-terraform/nexus-kp.pem infra-terraform/nexus-kp.pem ubuntu@3.148.228.118:/home/ubuntu/
```
# Copiar directorio ansible 
```
scp -i infra-terraform/nexus-kp.pem -r ansible/ ubuntu@3.148.228.118:/home/ubuntu/
```
# Configurar a la instancia publica 
```
infocmp -x | ssh -i infra-terraform/nexus-kp.pem ubuntu@<IP PUBLICA> -- tic -x -
ssh -i infra-terraform/nexus-kp.pem ubuntu@3.148.228.118
```
## Configurar inventory
Se deben acutalizar las IP y realizar una prueba de ping.
```
cd ansible
vi inventory 
```
Reemplzar las **XXX** por el dato correspondiente a la IP.
```
[nexus]
repositorio ansible_host=10.0.2.XXX ansible_user=ubuntu ansible_ssh_private_key_file=../nexus-kp.pem ansible_port=22

[docker]
registry ansible_host=10.0.2.XXX ansible_user=ubuntu ansible_ssh_private_key_file=../nexus-kp.pem ansible_port=22
```
Verificar que tenemos llegada a los servidores.
```
ansible all -m ping -i inventory 
```
## Instalar Nexus y Docker con Ansible 
```
ansible-playbook -i inventory playbook.yml 
```
# Ingresar a la instancia publica 
Previamente vamos a asignarle una contrasena a nuestro usuario _ubuntu_ porque \
nos lo va solicitar **Remmina**.
```
sudo passwd ubuntu 
```
Vamos a ingresar a la instancia publica desde **Remmina** (acceso remoto), esto con el \
proposito de configurar **Nexus** desde la UI. \
Abrimos **Remmina** seleccionamos el acceso remoto **servidor publico**, click derecho \
_Edit_ Cambiamos la **IP** por **XXX.XXX.XXX.XXX:3389** y le asignamos la contrasena \
que le acabmos de crear al usuario **ubuntu**. \
La IP Publica la vamos a obtner despues de que se aprovisione la infraestructura, \
luego de modificar damos click en **Save**, volvemos a dar click derecho sobre \
**servidor publico**->**Connect** y de esta forma ya estamos conectados a nuestro servidor publico. \
Ahora si podemos ingresar desde **Remmina** y nos va solicitar usuario y contrasena.
# Ingresar a servidor privado Nexus 
Debemos crear las llaves PGP para configurar **Nexus**. Nos encotramos en el \
servidor publico desde donde tenemos llegada a los servidores privados.
```
infocmp -x | ssh -i nexus-kp.pem ubuntu@10.0.2.XXX -- tic -x -
ssh -i nexus-kp.pem ubuntu@<IP_PRIVADA de la instacia Nexus>
ssh -i nexus-kp.pem ubuntu@10.0.2.XXX
```
## Crear llave GPG 
```
gpg --full-generate-key
```
## Listar llaves
```
gpg --list-keys --keyid-format LONG
```
### Exportar llave privada 
```
gpg --armor --export-secret-keys <REEMPLAZAR IDENTIFICADOR> > mi_llave_privada.asc
```
### Exportar llave publica 
```
gpg --armor --export <REEMPLAZAR IDENTIFICADOR> > mi_repositorio.pub
```
# Configurar Nexus 
Una ves dentro de la instancia publica abrimos el navegador y colocamos en la \
barra de navegacion la **IP PRIVADA Y PUERTO** de la instancia donde estamos intalando \
**Nexus**. \
Para obtener la contrasena del usuario **admin** ejecutamos el siguiente comando.
```
cat /opt/sonatype-work/nexus3/admin.password
```
Una ves ingresamos nos va solicitar que cambiemos la contrasena.
## Crear usuario
Nos vamos a dirigir **Settings**(Rueda dentada)->Security->User luego damos click en \
crear usuario.
## Crear repositorio Docker
Nos dirigimos a Repositories y luego damos click sobre **Create repository** y \
seleccionamos _docker \(hosted\)_, rellenamos el formulario: \
**Name**: docker_repository \
**HTTP**: 5000 \
**Deployment policy**: Allow deployment \
Todo lo demas lo dejamos como esta y damos click sobre el boton **Create repository**.
## Crear repositorio APT 
Nos dirigimos a **Repositories** y luego damos click sobre **Create repository** y \
seleccionamos _apt (hosted)_, le asignamos un nombre, distribucion y le agregamos la \
llave privada (mi_llave_privada.asc). \
**Name**: paquetes_internos \
**Distribution**: jammy \
Despues de ser creado nuestro repositorio debemos copiar la URL para poder realizar \
la instalacion de los paquetes en los servidores clientes.
# Configurar servidor cliente
Nos ubicamos en el servidor publico y desde ahi copiamos la llave para ingresar al \
servidor cliente.
```
scp -i nexus-kp.pem nexus-kp.pem ubuntu@<IP PRIVADA de la instancia cliente>:/home/ubuntu
scp -i nexus-kp.pem nexus-kp.pem ubuntu@10.0.2.xx:/home/ubuntu
```
## Ingresar al servidor cliente
```
infocmp -x | ssh -i nexus-kp.pem ubuntu@10.0.2.XXX -- tic -x -
ssh -i nexus-kp.pem ubuntu@<IP PRIVADA de la instancia cliente>
ssh -i nexus-kp.pem ubuntu@10.0.2.XXX
```
## Copiar llave publica PGP
Vamos a copiar la llave publica que se encuentra en el servidor Nexus
```
scp -i nexus-kp.pem ubuntu@<IP PRIVADA de la instancia nexus>:/home/ubuntu/mi_repositorio.pub .

scp -i nexus-kp.pem ubuntu@10.0.2.xx:/home/ubuntu/mi_repositorio.pub .
```
### Agregar llave publica PGP 
```
sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/nexus_internos.gpg mi_repositorio.pub
```
### Agregar repositorio 
```
sudo vi /etc/apt/sources.list.d/nexus_internos.sources
```

```
X-Reponame: Nexus_Paquetes_Internos
Types: deb
URIs: http://<IP PRIVADA instancia Nexux>:8081/repository/paquetes_internos/
Suites: jammy
Components: main
Signed-By: /etc/apt/trusted.gpg.d/nexus_internos.gpg
Trusted: yes
```
### Agregar usuario y contrasena para autenticar repositorio
```
sudo vi /etc/apt/auth.conf.d/nexus.conf
```

```
machine http://<IP PRIVADA instancia Nexus>:8081/repository/paquetes_internos/ login jon password xxxxxxx
machine http://10.0.2.XXX:8081/repository/paquetes_internos/ login jon password xxxxxxx 
```
#### Limpiar repositorio
```
sudo apt clean 
```
#### Actualizar repositorio 
```
sudo apt update 
```
# Verificar APT 
Vamos a verificar que nuestro paquete ya esta disponible para instalarse.
```
sudo apt search nginx-custom
sudo apt install nginx-custom 
```
Nos dirigimos a **Remmina**, ingresamos al servidor publico y abrimos el navegador \
y en la barra de navegacion colocamos la **IP PRIVADA** de la instancia cliente \
y debe aparecer nuestro **Nginx** personalizado.
# Configurar servidor Docker
Nos dirigimos al servidor Docker para configura lo para que pueda subir y descargar \
imagnes del repositorio privado.
## Ingresar al servidor
Debemos estar dentro del servidor publico y desde ahi ejecutamos
```
infocmp -x | ssh -i nexus-kp.pem ubuntu@10.0.2.XXX -- tic -x -
ssh -i nexus-kp.pem ubuntu@10.0.2.XXX
```
## Agregar configuracion
Esta configuracion nos va permitir subir y descargar imagenes del registry.
```
sudo mkdir -p /etc/docker
echo '{"insecure-registries":["10.0.2.XXX:5000"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
docker info | tail -n 10
```
# Verificar Docker 
## Iniciar sesion 
```
docker login -u jon 10.0.2.XXX:5000
```
## Crear imagen 
```
docker pull alpine:latest
docker tag alpine:latest 10.0.2.XXX:5000/alpine:jon 
docker push 10.0.2.XXX:5000/alpine:jon 
```
### Ver catalogo
```
curl -u jon http://10.0.2.XXX:5000/v2/_catalog 
```
### Descargar imagenes desde Nexus
```
docker pull 10.0.2.XXX:5000/alpine:jon 
```
# Eliminar infraestructura
```
terraform plan -destroy --out main-plan-destroy.tfplan
terraform apply main-plan-destroy.tfplan
```
# OTROS COMANDOS
#### Ver las IP's publicas y privadas
```
terraform output
```
#### Listar tipos de instancias disponibles para tier
```
aws ec2 describe-instance-types \
    --filters Name=free-tier-eligible,Values=true \
    --region us-east-2 \
    --query "InstanceTypes[].{Type:InstanceType,CPU:VCpuInfo.DefaultVCpus,Memory:MemoryInfo.SizeInMiB}" \
    --output table
```
#### Ver estado de las instancias
```
aws ec2 describe-instances \
    --filters Name=tag:USER,Values=SNOW \
    --query "Reservations[].Instances[].{ID:InstanceId,ESTADO:State.Name,Nombre:Tags[?Key=='Name'].Value | [0]}" \
    --output table
```
#### Ver VPCS 
```
aws ec2 describe-vpcs \
    --filters Name=tag:USER,Values=SNOW \
    --query "Vpcs[].{VPC:VpcId,Nombre:Tags[?Key=='Name'].Value | [0],Estado:State}" \
    --output table 
```
#### Ver Subnets 
```
aws ec2 describe-subnets \
    --filter Name=tag:USER,Values=SNOW \
    --query "Subnets[].{Nombre:Tags[?Key=='Name'].Value | [0],Estado:State}" \
    --output table 
```
#### Ver SG 
```
aws ec2 describe-security-groups \
    --filter Name=tag:USER,Values=SNOW \
    --query "SecurityGroups[].{Nombre:Tags[?Key=='Name'].Value | [0],Vpc:VpcId}" \
    --output table
```

