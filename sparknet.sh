#!/bin/bash

# === Banner colorido ===
banner=(
"  ____                   _    _   _      _    "
" / ___| _ __   __ _ _ __| | _| \\ | | ___| |_  "
" \\___ \\| '_ \\ / _\` | '__| |/ /  \\| |/ _ \\ __| "
"  ___) | |_) | (_| | |  |   <| |\\  |  __/ |_  "
" |____/| .__/ \\__,_|_|  |_|\\_\\_| \\_|\\___|\\__| "
"       |_|                                    "
)
colors=(127 99 93 69 39 33)

function mostrar_banner() {
  for i in "${!banner[@]}"; do
    echo -e "\e[38;5;${colors[i]}m${banner[i]}\e[0m"
  done
  echo ""
}

# === Funciones ===

function instalar_udp_custom() {
  echo "🔄 Instalando UDP Http-custom desde GitHub..."
  if [ -d /opt/udp-custom ]; then
    echo "📁 El directorio /opt/udp-custom ya existe, actualizando..."
    cd /opt/udp-custom && git pull
  else
    git clone https://github.com/http-custom/udp-custom.git /opt/udp-custom
  fi
  cd /opt/udp-custom || { echo "❌ No se pudo acceder a /opt/udp-custom"; return 1; }
  chmod +x install.sh
  ./install.sh
  echo "✅ UDP Http-custom instalado."
}

function instalar_udp_zivpn() {
  echo "🔄 Instalando UDP Zivpn..."
  wget -q --show-progress -O zi.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh
  chmod +x zi.sh
  ./zi.sh
  echo "✅ UDP Zivpn instalado."
}

function desinstalar_udp_zivpn() {
  echo "🔄 Desinstalando UDP Zivpn..."
  wget -q --show-progress -O ziun.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/uninstall.sh
  chmod +x ziun.sh
  ./ziun.sh
  echo "✅ UDP Zivpn desinstalado."
}

function instalar_3xui() {
  echo "🔄 Instalando 3x-ui..."
  bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
  echo "✅ 3x-ui instalado."
}

function desinstalar_3xui() {
  echo "🔄 Desinstalando 3x-ui..."
  x-ui uninstall
  echo "✅ 3x-ui desinstalado."
}

function arreglar_iptables() {
  echo "🔧 Aplicando reglas iptables para ZIVPN..."

  iptables -t nat -D PREROUTING 2>/dev/null
  iptables -t nat -D PREROUTING 2>/dev/null

  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  iptables -t nat -A PREROUTING -p udp --dport 1:65535 -j DNAT --to-destination :36712
  iptables -I INPUT -p udp --dport 36712 -j ACCEPT

  echo "✅ Reglas iptables aplicadas."
}

function actualizar_script() {
  echo "🔄 Comprobando actualización del script..."
  read -rp "¿Deseas actualizar el script a la última versión disponible en GitHub? (y/n): " respuesta
  if [[ "$respuesta" == "y" || "$respuesta" == "Y" ]]; then
    ruta_local="$(realpath "$0")"
    url="https://raw.githubusercontent.com/Dex1399/SparknetVps/main/sparknet.sh"
    if curl --output /tmp/sparknet.sh --silent --fail "$url"; then
      chmod +x /tmp/sparknet.sh
      cp /tmp/sparknet.sh "$ruta_local"
      echo "✅ Script actualizado correctamente."
    else
      echo "❌ No se pudo descargar la versión más reciente desde GitHub."
    fi
  else
    echo "❎ Actualización cancelada por el usuario."
  fi
}

function menu_udp_custom() {
  while true; do
    clear
    mostrar_banner
    echo "==============================================="
    echo "         ⚡ Submenú UDP Http-custom             "
    echo "==============================================="
    echo "1) ⚙️  Instalar UDP Http-custom"
    echo "2) 🔙 Volver"
    echo "-----------------------------------------------"
    read -rp "Selecciona una opción: " opcion_hc

    case $opcion_hc in
      1) instalar_udp_custom ;;
      2) return ;;
      *) echo "❌ Opción inválida. Intenta nuevamente." ;;
    esac

    echo -e "\nPresiona ENTER para continuar..."
    read -r
  done
}

function menu_zivpn() {
  while true; do
    clear
    mostrar_banner
    echo "==============================================="
    echo "            🌐 Submenú UDP Zivpn               "
    echo "==============================================="
    echo "1) ⚙️  Instalar UDP Zivpn"
    echo "2) 🗑️  Desinstalar UDP Zivpn"
    echo "3) 🔙 Volver"
    echo "-----------------------------------------------"
    read -rp "Selecciona una opción: " opcion_z

    case $opcion_z in
      1) instalar_udp_zivpn ;;
      2) desinstalar_udp_zivpn ;;
      3) return ;;
      *) echo "❌ Opción inválida. Intenta nuevamente." ;;
    esac

    echo -e "\nPresiona ENTER para continuar..."
    read -r
  done
}

function menu_3xui() {
  while true; do
    clear
    mostrar_banner
    echo "==============================================="
    echo "             📡 Submenú 3x-ui                  "
    echo "==============================================="
    echo "1) ⚙️  Instalar 3x-ui"
    echo "2) 🗑️  Desinstalar 3x-ui"
    echo "3) 🔙 Volver"
    echo "-----------------------------------------------"
    read -rp "Selecciona una opción: " opcion_x

    case $opcion_x in
      1) instalar_3xui ;;
      2) desinstalar_3xui ;;
      3) return ;;
      *) echo "❌ Opción inválida. Intenta nuevamente." ;;
    esac

    echo -e "\nPresiona ENTER para continuar..."
    read -r
  done
}

function menu_principal() {
  while true; do
    clear
    mostrar_banner
    echo "=========== Menú de Instalación y Configuración ==========="
    echo "1) UDP Http-custom"
    echo "2) UDP Zivpn"
    echo "3) 3x-ui"
    echo "4) Arreglar reglas iptables para Zivpn"
    echo "5) Salir"
    echo "6) 🔄 Actualizar script desde GitHub"
    echo "------------------------------------------------------------"
    read -rp "Selecciona una opción: " opcion

    case $opcion in
      1) menu_udp_custom ;;
      2) menu_zivpn ;;
      3) menu_3xui ;;
      4) arreglar_iptables ;;
      5) echo "👋 Saliendo..."; exit 0 ;;
      6) actualizar_script ;;
      *) echo "❌ Opción inválida. Intenta nuevamente." ;;
    esac

    echo -e "\nPresiona ENTER para continuar..."
    read -r
  done
}

# === Ejecutar menú ===
menu_principal
