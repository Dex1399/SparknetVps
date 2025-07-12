#!/bin/bash
# Script de gestión de usuarios para Hysteria con auto-instalación
# Compatible con config.json que usa autenticación por lista de usuarios

# Verificar si es root
if [ "$(id -u)" != "0" ]; then
    echo "Este script debe ejecutarse como root" 1>&2
    exit 1
fi

# Configuración
CONFIG_FILE="/root/UDPMOD/config.json"
DB_FILE="/etc/hysteria/users.db"
LOG_FILE="/var/log/hysteria_activity.log"
SERVICE_NAME="udpmod"

# Colores para la interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Función para limpiar JSON
clean_json() {
    # Eliminar caracteres no ASCII y espacios de ancho cero
    sed -i 's/[^[:print:]]//g' "$CONFIG_FILE"
    # Eliminar espacios al final de las líneas
    sed -i 's/[[:space:]]*$//' "$CONFIG_FILE"
    # Eliminar comentarios (líneas que comienzan con //)
    sed -i '/^[[:space:]]*\/\//d' "$CONFIG_FILE"
}

# Función para instalar dependencias
install_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Instalando jq...${NC}"
        apt-get update > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}jq instalado correctamente${NC}"
        else
            echo -e "${RED}Error al instalar jq. Instálelo manualmente con:"
            echo -e "apt-get update && apt-get install jq${NC}"
            exit 1
        fi
    fi
}

# Inicializar archivos y directorios
initialize_files() {
    # Crear directorio de configuración
    mkdir -p "$(dirname "$DB_FILE")"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Crear archivo de base de datos si no existe
    if [ ! -f "$DB_FILE" ]; then
        touch "$DB_FILE"
        chmod 600 "$DB_FILE"
        echo -e "${GREEN}Base de datos creada: $DB_FILE${NC}"
    fi
    
    # Crear archivo de log
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        echo -e "${GREEN}Archivo de log creado: $LOG_FILE${NC}"
    fi
    
    # Verificar existencia de config.json
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}ERROR: No se encuentra $CONFIG_FILE${NC}"
        echo -e "Asegúrese de tener instalado Hysteria correctamente"
        exit 1
    fi
}

# Registrar actividad
log_event() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Validar formato JSON
validate_json() {
    if ! jq empty "$CONFIG_FILE" &>/dev/null; then
        echo -e "${RED}ERROR: config.json tiene formato inválido${NC}"
        log_event "[ERROR] Configuración JSON inválida - Verifique manualmente"
        echo -e "${YELLOW}Use 'jq . $CONFIG_FILE' para diagnosticar el error${NC}"
        exit 1
    fi
}

# Calcular días restantes
calculate_days_left() {
    local exp_date=$1
    local today_sec=$(date +%s)
    local exp_sec=$(date -d "$exp_date" +%s 2>/dev/null)
    
    if [ -z "$exp_sec" ] || [ "$exp_sec" -lt "$today_sec" ]; then
        echo "EXPIRADO"
    else
        echo $(( (exp_sec - today_sec) / 86400 ))
    fi
}

# Función para eliminar usuario de config.json
remove_user_from_config() {
    local username=$1
    jq --arg user "$username" '.auth.config = [.auth.config[] | select(split(":")[0] != $user)]' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
}

# Función para reiniciar el servicio con verificación
restart_hysteria_service() {
    echo -e "${YELLOW}Reiniciando servicio Hysteria...${NC}"
    systemctl restart "$SERVICE_NAME"
    sleep 1  # Esperar un momento para que el servicio se reinicie
    
    # Verificar estado
    service_status=$(systemctl is-active "$SERVICE_NAME")
    
    if [ "$service_status" == "active" ]; then
        echo -e "${GREEN}Servicio reiniciado correctamente!${NC}"
        log_event "[SERVICIO] Reinicio automático exitoso"
    else
        echo -e "${RED}ERROR: No se pudo reiniciar el servicio${NC}"
        log_event "[ERROR] Fallo al reiniciar servicio"
        echo "Consulte los logs con: journalctl -u $SERVICE_NAME"
    fi
}

# Menú principal
show_menu() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${YELLOW}          PANEL DE GESTIÓN HYSTERIA v2.0${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${BLUE}1)${NC} Agregar nuevo usuario"
    echo -e "${BLUE}2)${NC} Cambiar OBFS"
    echo -e "${BLUE}3)${NC} Listar usuarios existentes"
    echo -e "${BLUE}4)${NC} Renovar usuario"
    echo -e "${BLUE}5)${NC} Eliminar usuario"
    echo -e "${BLUE}6)${NC} Verificar expiraciones ahora"
    echo -e "${BLUE}7)${NC} Ver registro de actividad"
    echo -e "${BLUE}8)${NC} Reiniciar servicio"
    echo -e "${RED}9)${NC} Salir"
    echo -e "${CYAN}==================================================${NC}"
    read -p "Seleccione una opción [1-9]: " choice
}

# Función para agregar usuario
add_user() {
    echo -e "\n${CYAN}============ AGREGAR NUEVO USUARIO ============${NC}"
    
    # Solicitar datos
    while true; do
        read -p "Nombre de usuario: " username
        if [ -z "$username" ]; then
            echo -e "${RED}El usuario no puede estar vacío${NC}"
        elif grep -q "^$username:" "$DB_FILE"; then
            echo -e "${RED}El usuario ya existe${NC}"
        else
            break
        fi
    done
    
    read -p "Contraseña (dejar en blanco para generar aleatoria): " password
    if [ -z "$password" ]; then
        password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
        echo -e "${YELLOW}Contraseña generada: ${GREEN}$password${NC}"
    fi
    
    while true; do
        read -p "Días de validez: " days_valid
        if [[ "$days_valid" =~ ^[0-9]+$ ]] && [ "$days_valid" -gt 0 ]; then
            break
        else
            echo -e "${RED}Días inválidos. Debe ser un número mayor a 0${NC}"
        fi
    done
    
    # Calcular fechas
    local creation_date=$(date +%Y-%m-%d)
    local exp_date=$(date -d "$creation_date + $days_valid days" +%Y-%m-%d)
    
    # Agregar a base de datos
    echo "$username:$password:$creation_date:$exp_date:ACTIVO" >> "$DB_FILE"
    
    # Actualizar config.json (formato array)
    jq --arg user "$username" --arg pass "$password" '.auth.config += ["\($user):\($pass)"]' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    
    # Registrar evento
    log_event "[USUARIO CREADO] $username (Expira: $exp_date)"
    echo -e "${GREEN}Usuario $username creado exitosamente!${NC}"
    
    # Mostrar días restantes
    days_left=$(calculate_days_left "$exp_date")
    if [[ "$days_left" != "EXPIRADO" ]]; then
        echo -e "Expiración: $exp_date (${days_left} días restantes)"
    else
        echo -e "Expiración: $exp_date (${RED}EXPIRADO${NC})"
    fi
    
    # REINICIO AUTOMÁTICO
    restart_hysteria_service
}

# Función para cambiar OBFS
change_obfs() {
    echo -e "\n${CYAN}=============== CAMBIAR OBFS ================${NC}"
    
    # Mostrar valor actual
    current_obfs=$(jq -r '.obfs' "$CONFIG_FILE")
    echo -e "OBFS actual: ${YELLOW}$current_obfs${NC}"
    
    # Solicitar nuevo valor
    read -p "Nuevo valor OBFS: " new_obfs
    
    # Validar entrada
    if [ -z "$new_obfs" ]; then
        echo -e "${RED}ERROR: El OBFS no puede estar vacío${NC}"
        return
    fi
    
    # Actualizar config.json
    jq --arg obfs "$new_obfs" '.obfs = $obfs' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    
    # Registrar evento
    log_event "[OBFS CAMBIADO] Nuevo valor: $new_obfs"
    echo -e "${GREEN}OBFS actualizado correctamente!${NC}"
    
    # Reiniciar servicio
    read -p "¿Reiniciar servicio ahora? (s/n): " restart
    if [[ "$restart" == "s" ]]; then
        restart_hysteria_service
    fi
}

# Función para listar usuarios
list_users() {
    echo -e "\n${CYAN}============= USUARIOS REGISTRADOS =============${NC}"
    
    if [ ! -s "$DB_FILE" ]; then
        echo -e "${YELLOW}No hay usuarios registrados${NC}"
        return
    fi
    
    # Cabecera de la tabla
    printf "%-20s %-20s %-15s %-15s %-15s %-10s\n" "Usuario" "Contraseña" "Creación" "Expiración" "Restantes" "Estado"    echo "--------------------------------------------------------------------------------------------"
    
    # Procesar cada usuario
    while IFS=: read -r user pass creation exp_date status; do
        # Calcular días restantes
        days_left=$(calculate_days_left "$exp_date")
        
        # Determinar estado actual
        if [ "$status" == "ACTIVO" ] && [[ "$days_left" == "EXPIRADO" ]]; then
            status="EXPIRADO"
            # Actualizar estado en base de datos
            sed -i "/^$user:/s/:ACTIVO$/:EXPIRADO/" "$DB_FILE"
            # Eliminar de config.json
            remove_user_from_config "$user"
        fi
        
        # Formatear salida según estado
        if [ "$status" == "ACTIVO" ]; then
            printf "%-20s %-20s %-15s %-15s ${GREEN}%-15s${NC} ${GREEN}%-10s${NC}\n" "$user" "$pass" "$creation" "$exp_date" "$days_left días" "$status"
        elif [ "$status" == "EXPIRADO" ]; then
            printf "%-20s %-20s %-15s %-15s ${RED}%-15s${NC} ${RED}%-10s${NC}\n" "$user" "$pass" "$creation" "$exp_date" "EXPIRADO" "$status"
        else
            printf "%-20s %-20s %-15s %-15s %-15s %-10s\n" "$user" "$pass" "$creation" "$exp_date" "$days_left días" "$status"
        fi
    done < "$DB_FILE"
}

# Función para renovar usuario
renew_user() {
    echo -e "\n${CYAN}=============== RENOVAR USUARIO ===============${NC}"
    
    # Mostrar usuarios expirados
    expired_users=()
    while IFS=: read -r user pass creation exp_date status; do
        if [ "$status" == "EXPIRADO" ]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"
    
    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "${YELLOW}No hay usuarios expirados para renovar${NC}"
        return
    fi
    
    echo "Usuarios expirados:"
    for i in "${!expired_users[@]}"; do
        echo "$((i+1)). ${expired_users[$i]}"
    done
    
    # Seleccionar usuario
    read -p "Seleccione un usuario (número): " user_num
    if ! [[ "$user_num" =~ ^[0-9]+$ ]] || [ "$user_num" -lt 1 ] || [ "$user_num" -gt ${#expired_users[@]} ]; then
        echo -e "${RED}Selección inválida${NC}"
        return
    fi
    
    local username="${expired_users[$((user_num-1))]}"
    read -p "Nuevos días de validez para $username: " new_days
    
    # Validar días
    if ! [[ "$new_days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Días inválidos${NC}"
        return
    fi
    
    # Calcular nueva fecha
    local new_exp_date=$(date -d "+$new_days days" +%Y-%m-%d)
    
    # Actualizar base de datos
    sed -i "/^$username:/s/:EXPIRADO$/:ACTIVO/" "$DB_FILE"
    sed -i "/^$username:/s/:[^:]*$/:$new_exp_date/" "$DB_FILE"
    
    # Buscar contraseña
    user_data=$(grep "^$username:" "$DB_FILE")
    IFS=: read -r user pass creation old_exp status <<< "$user_data"
    
    # Agregar a config.json (formato array)
    jq --arg user "$username" --arg pass "$pass" '.auth.config += ["\($user):\($pass)"]' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    
    # Registrar evento
    log_event "[USUARIO RENOVADO] $username (Nueva expiración: $new_exp_date)"
    echo -e "${GREEN}Usuario $username renovado exitosamente!${NC}"
    echo -e "Nueva fecha de expiración: $new_exp_date"
    
    # REINICIO AUTOMÁTICO
    restart_hysteria_service
}

# Función para eliminar usuario
delete_user() {
    echo -e "\n${CYAN}=============== ELIMINAR USUARIO ===============${NC}"
    
    # Mostrar todos los usuarios
    all_users=()
    while IFS=: read -r user pass creation exp_date status; do
        all_users+=("$user:$status:$exp_date")
    done < "$DB_FILE"
    
    if [ ${#all_users[@]} -eq 0 ]; then
        echo -e "${YELLOW}No hay usuarios registrados${NC}"
        return
    fi
    
    echo "Todos los usuarios:"
    for i in "${!all_users[@]}"; do
        IFS=: read -r user status exp_date <<< "${all_users[$i]}"
        printf "%2d) %-20s %-10s %s\n" "$((i+1))" "$user" "$status" "$exp_date"
    done
    
    # Seleccionar usuario
    read -p "Seleccione un usuario para eliminar (número): " user_num
    if ! [[ "$user_num" =~ ^[0-9]+$ ]] || [ "$user_num" -lt 1 ] || [ "$user_num" -gt ${#all_users[@]} ]; then
        echo -e "${RED}Selección inválida${NC}"
        return
    fi
    
    IFS=: read -r username status exp_date <<< "${all_users[$((user_num-1))]}"
    
    # Confirmar eliminación
    read -p "¿CONFIRMA ELIMINAR PERMANENTEMENTE A '$username'? (s/n): " confirm
    if [[ "$confirm" != "s" ]]; then
        echo -e "${YELLOW}Eliminación cancelada${NC}"
        return
    fi
    
    # Eliminar de config.json
    remove_user_from_config "$username"
    
    # Eliminar de base de datos
    sed -i "/^$username:/d" "$DB_FILE"
    
    # Registrar evento
    log_event "[USUARIO ELIMINADO] $username"
    echo -e "${GREEN}Usuario $username eliminado permanentemente!${NC}"
    
    # REINICIO AUTOMÁTICO
    restart_hysteria_service
}

# Función para verificar expiraciones
check_expirations() {
    echo -e "\n${CYAN}========= VERIFICAR EXPIRACIONES AHORA =========${NC}"
    count=0
    
    while IFS=: read -r user pass creation exp_date status; do
        # Calcular días restantes
        days_left=$(calculate_days_left "$exp_date")
        
        if [ "$status" == "ACTIVO" ] && [[ "$days_left" == "EXPIRADO" ]]; then
            # Actualizar estado
            sed -i "/^$user:/s/:ACTIVO$/:EXPIRADO/" "$DB_FILE"
            
            # Eliminar de config.json
            remove_user_from_config "$user"
            
            # Registrar evento
            log_event "[EXPIRACIÓN AUTOMÁTICA] $user"
            echo -e "Usuario ${RED}$user${NC} marcado como expirado"
            ((count++))
        fi
    done < "$DB_FILE"
    
    if [ $count -eq 0 ]; then
        echo -e "${GREEN}No se encontraron usuarios expirados${NC}"
    else
        echo -e "${YELLOW}Se actualizaron $count usuarios expirados${NC}"
        # REINICIO AUTOMÁTICO SOLO SI HUBO CAMBIOS
        restart_hysteria_service
    fi
}

# Función para ver registro de actividad
show_activity_log() {
    echo -e "\n${CYAN}============ REGISTRO DE ACTIVIDAD ============${NC}"
    
    if [ ! -s "$LOG_FILE" ]; then
        echo -e "${YELLOW}El registro de actividad está vacío${NC}"
        return
    fi
    
    # Mostrar las últimas 50 líneas con colores
    tail -n 50 "$LOG_FILE" | while IFS= read -r line; do
        if [[ "$line" == *"CREADO"* ]] || [[ "$line" == *"RENOVADO"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" == *"ELIMINADO"* ]] || [[ "$line" == *"EXPIRACIÓN"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" == *"CAMBIADO"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ "$line" == *"ERROR"* ]]; then
            echo -e "${RED}$line${NC}"
        else
            echo -e "${BLUE}$line${NC}"
        fi
    done
}

# Función para reiniciar servicio (manual)
restart_service() {
    echo -e "\n${CYAN}============= REINICIAR SERVICIO ==============${NC}"
    
    read -p "¿CONFIRMA REINICIAR EL SERVICIO HYSTERIA? (s/n): " confirm
    if [[ "$confirm" != "s" ]]; then
        echo -e "${YELLOW}Operación cancelada${NC}"
        return
    fi
    
    restart_hysteria_service
}

#--------- INICIO DEL SCRIPT ---------#
# Instalar dependencias si faltan
install_dependencies

# Inicializar archivos y directorios
initialize_files

# Limpiar y validar JSON
clean_json
validate_json

# Bucle principal del menú
while true; do
    show_menu
    case $choice in
        1) add_user ;;
        2) change_obfs ;;
        3) list_users ;;
        4) renew_user ;;
        5) delete_user ;;
        6) check_expirations ;;
        7) show_activity_log ;;
        8) restart_service ;;
        9) 
            echo -e "${GREEN}Saliendo...${NC}"
            log_event "[SISTEMA] Script finalizado"
            exit 0 
            ;;
        *) 
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
    
    echo
    read -p "Presione Enter para continuar..."
done
