#!/bin/bash

# Eliminar este script después de ejecución
rm -rf $(pwd)/$0

# Solicitar dominio al usuario
read -p "Ingresa tu dominio: " domain

# Actualizar sistema e instalar dependencias
apt update -y
apt upgrade -y
apt install wget -y

# Crear directorio de trabajo
mkdir -p /root/UDPMOD
cd /root/UDPMOD

# Descargar archivos desde GitHub
base_url="https://raw.githubusercontent.com/Dex1399/SparknetVps/main/UDPMOD"
files=(
    "config.json"
    "hysteria-linux-amd64"
    "hysteria-v1-linux-amd64"
    "hysteria-v2-linux-amd64"
    "hysteria_manager.sh"
    "udpmod.service"
)

for file in "${files[@]}"; do
    wget -q "${base_url}/${file}"
    [ -x "${file}" ] || chmod +x "${file}" 2>/dev/null
done

# Dar permisos a binarios Hysteria
chmod +x hysteria-*

# Generar OBFS aleatorio
OBFS=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)

# Obtener interfaz de red
interfas=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -n 1)

# Reemplazar interfaz en el servicio
sed -i "s/INTERFACE/${interfas}/g" udpmod.service

# Generar certificados SSL
openssl genrsa -out udpmod.ca.key 2048
openssl req -new -x509 -days 3650 -key udpmod.ca.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=Udpmod Root CA" -out udpmod.ca.crt
openssl req -newkey rsa:2048 -nodes -keyout udpmod.server.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=${domain}" -out udpmod.server.csr
openssl x509 -req -extfile <(printf "subjectAltName=DNS:%s,DNS:%s" "$domain" "$domain") -days 3650 -in udpmod.server.csr -CA udpmod.ca.crt -CAkey udpmod.ca.key -CAcreateserial -out udpmod.server.crt

# Personalizar configuración
sed -i "s/setobfs/${OBFS}/g" config.json

# Instalar servicio
mv udpmod.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable udpmod
systemctl start udpmod

# Verificar estado
if ! systemctl is-active --quiet udpmod; then
    echo "Error al iniciar el servicio. Verificando logs..."
    journalctl -u udpmod -b --no-pager -n 20
    exit 1
fi

# =================================================================
# NUEVAS SECCIONES AGREGADAS
# =================================================================

# Configurar comando de administración
echo "Configurando comando de administración..."
chmod +x /root/UDPMOD/hysteria_manager.sh
ln -sf /root/UDPMOD/hysteria_manager.sh /usr/local/bin/hysteria-mgr

# Crear alias permanente para todos los usuarios
for user_home in /home/* /root; do
    if [ -d "$user_home" ] && [ -f "$user_home/.bashrc" ]; then
        if ! grep -q "alias hysteria-mgr" "$user_home/.bashrc"; then
            echo "alias hysteria-mgr='sudo /usr/local/bin/hysteria-mgr'" >> "$user_home/.bashrc"
        fi
    fi
done

# Actualizar PATH inmediatamente
echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
source /etc/profile > /dev/null 2>&1

# =================================================================
# FIN DE NUEVAS SECCIONES
# =================================================================

# Mostrar información
echo "obfs: ${OBFS}" > data
echo "port: 36712" >> data
echo "rango de puertos: 20000:39999" >> data
echo "--------------------------------"
cat data
echo "--------------------------------"

# Limpieza
rm -f udpmod.server.csr udpmod.ca.srl 2>/dev/null

# Mensaje final con instrucciones
echo -e "\n\n================================================================"
echo -e "INSTALACIÓN COMPLETADA CORRECTAMENTE"
echo -e "================================================================\n"
echo -e "Para gestionar usuarios, utiliza el siguiente comando:"
echo -e "   ${YELLOW}hysteria-mgr${NC}"
echo -e ""
echo -e "Este comando estará disponible:"
echo -e "- En nuevas terminales inmediatamente"
echo -e "- En esta terminal después de ejecutar:"
echo -e "      ${YELLOW}source /etc/profile${NC}"
echo -e "================================================================"
echo -e "Nota: Si no funciona inmediatamente, cierra y abre una nueva terminal"
echo -e "================================================================\n"
