#!/bin/bash
#
# Copyright (c) 2026 Kyz Applications. Todos los derechos reservados.
# Uso permitido según LICENSE. Prohibida la copia, modificación o
# redistribución de este script sin autorización previa y por escrito
# de Kyz Applications.
#
set -o pipefail
clear

export DEBIAN_FRONTEND=noninteractive
source /etc/os-release

SUPPORT_LEVEL="unsupported"
case "$ID:$VERSION_ID" in
  ubuntu:20.04) SUPPORT_LEVEL="legacy" ;;
  ubuntu:22.04) SUPPORT_LEVEL="recommended" ;;
  ubuntu:24.04) SUPPORT_LEVEL="supported" ;;
  debian:11) SUPPORT_LEVEL="legacy" ;;
  debian:12) SUPPORT_LEVEL="supported" ;;
  *) SUPPORT_LEVEL="unsupported" ;;
esac

apt-get install figlet curl wget jq unzip -y > /dev/null 2>&1
apt install lolcat -y > /dev/null 2>&1

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

step() {
    local msg="$1"; shift
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    tput civis 2>/dev/null
    ( "$@" ) > /dev/null 2>&1 &
    local pid=$!

    printf "  ${YELLOW}• %s${NC}" "$msg"
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#spin} ))
        printf "\r  ${YELLOW}• %s ${CYAN}%s${NC}" "$msg" "${spin:$i:1}"
        sleep 0.1
    done
    wait "$pid"
    local status=$?
    tput cnorm 2>/dev/null

    if [ $status -eq 0 ]; then
        printf "\r  ${GREEN}✔ %s${NC}\n" "$msg"
    else
        printf "\r  ${RED}✘ %s${NC}\n" "$msg"
    fi
    return $status
}

mostrar_banner_instalador() {
    clear
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       >>>>>  🐉  ${YELLOW}${BOLD}Installer KyzAuto${NC}${BLUE}  ✸  ${YELLOW}${BOLD}Por Nokasvip${NC}${BLUE}  🐉  <<<<<${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Dominio:${NC} ${CYAN}${DOMAIN:-N/A}${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}              Instalador de Script SSH Kyz Auto${NC}"
echo -e "${CYAN}        (AutoScript: SSH/Xray/TFN-UDP)${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}Sistemas Operativos Soportados:${NC}"
echo -e "${GREEN}  ✔ Debian 12              (Recomendado)${NC}"
echo -e "${GREEN}  ✔ Debian 11              (Soporte Legado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 24.04           (Soportado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 22.04           (Recomendado)${NC}"
echo -e "${GREEN}  ✔ Ubuntu 20.04           (Soporte Legado)${NC}"
echo -e "${CYAN}============================================================${NC}"
sleep 5

if [ "$SUPPORT_LEVEL" = "unsupported" ]; then
  echo -e "${GREEN}Este instalador solo soporta Ubuntu 20.04/22.04/24.04 y Debian 11/12.${NC}"
  echo -e "${CYAN}Detectado: ${ID} ${VERSION_ID}${NC}"
  exit 1
fi

clear

echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                 Configuración de Dominio${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e "  ${YELLOW}🌐 Dominio/Subdominio para Xray${NC} ${WHITE}(enter = usar la IP):${NC} ")" -e -i "$(curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')" DOMAIN
export DOMAIN
echo ""

preparar_dns_certbot() {
    apt-get update -y > /dev/null 2>&1
    command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils > /dev/null 2>&1
    command -v certbot >/dev/null 2>&1 || apt-get install -y certbot > /dev/null 2>&1
}
step "Preparando herramientas de DNS/SSL..." preparar_dns_certbot

mkdir -p /etc/xray > /dev/null 2>&1
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    USE_LETSENCRYPT=false
    echo -e "  ${CYAN}ℹ Se usará un certificado autofirmado para la IP ${WHITE}$DOMAIN${NC}"
    echo -e "  ${YELLOW}⚠ Los clientes deberán activar 'allowInsecure' para el TLS en el puerto 443.${NC}"
else
    USE_LETSENCRYPT=true
    echo -e "  ${CYAN}ℹ Verificando que ${WHITE}$DOMAIN${NC}${CYAN} resuelva a la IP del servidor...${NC}"
    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null | tail -1)
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        echo -e "  ${RED}✘ ERROR: El dominio $DOMAIN no apunta a la IP $SERVER_IP.${NC}"
        echo -e "  ${RED}  Crea un registro A en tu DNS y vuelve a ejecutar el script.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✔ Dominio verificado.${NC}"
    systemctl stop xray 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    solicitar_certificado_le() {
        certbot certonly --standalone --non-interactive --agree-tos --email "admin@$DOMAIN" -d "$DOMAIN" > /dev/null 2>&1
    }
    if ! step "Solicitando certificado SSL (Let's Encrypt)..." solicitar_certificado_le; then
        echo -e "  ${RED}✘ No se pudo emitir el certificado Let's Encrypt para $DOMAIN.${NC}"
        exit 1
    fi
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "letsencrypt" > /etc/xray/cert_type
fi

if [ "$USE_LETSENCRYPT" = false ]; then
    generar_cert_autofirmado() {
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
          -keyout /etc/xray/xray.key \
          -out /etc/xray/xray.crt \
          -subj "/CN=${DOMAIN}/O=KyzTunnel/C=US" > /dev/null 2>&1
    }
    step "Generando certificado autofirmado..." generar_cert_autofirmado
    echo "selfsigned" > /etc/xray/cert_type
else
    cp "$CERT_PATH" /etc/xray/xray.crt > /dev/null 2>&1
    cp "$KEY_PATH" /etc/xray/xray.key > /dev/null 2>&1
fi
chmod 644 /etc/xray/xray.crt > /dev/null 2>&1
chmod 600 /etc/xray/xray.key > /dev/null 2>&1
mkdir -p /etc/stunnel > /dev/null 2>&1
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
chmod 600 /etc/stunnel/stunnel.pem > /dev/null 2>&1
chown root:root /etc/stunnel/stunnel.pem > /dev/null 2>&1

SSH_Port1='22'
SSH_Port2='299'
Stunnel_Port='127.0.0.1:4443'
Stunnel_Port_Num='4443' 
Squid_Port1='3128'
Squid_Port2='8000'
WsPorts=('10080' '25' '2082' '2086')  
WsPort='10080'  
MainPort='666' 

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                 Configuración de SlowDNS${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e "  ${YELLOW}🌐 Nameserver de SlowDNS${NC} ${WHITE}(enter = predeterminado):${NC} ")" -e -i "ns-miami.hexapps.app" Nameserver
echo ""
Serverkey='819d82813183e4be3ca1ad74387e47c0c993b81c601b2d1473a3f47731c404ae'
Serverpub='7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59'

UDP_PORT=":36712"
OBFS="socket"

clear
sleep 1.5
Nginx_Port='85' 
Dns_1='1.1.1.1' 
Dns_2='1.0.0.1'
MyVPS_Time='Africa/Accra'
My_Chat_ID='6857779956'
My_Bot_Key='8710991931:AAEk7mdyVamfxX7mTvO3HE_stV_zwEasdd'



systemctl daemon-reload; systemctl enable telegram-admin-bot.service; systemctl start telegram-admin-bot.service

function ip_address(){
  local IP="$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipv4.icanhazip.com 2>/dev/null )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipinfo.io/ip 2>/dev/null )"
  [ ! -z "${IP}" ] && echo "${IP}" || echo
} 
IPADDR="$(ip_address)"

mostrar_banner_instalador

actualizar_sistema() { apt-get update -y > /dev/null 2>&1; }
step "Actualizando (Apt Update)..." actualizar_sistema

systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null

SSH_SERVICE="ssh"; STUNNEL_SERVICE="stunnel4"; SQUID_SERVICE="squid"; SSLH_SERVICE="sslh"; NGINX_SERVICE="nginx"; SFTP_SUBSYSTEM="internal-sftp"

mkdir -p /etc/stunnel /etc/nginx/conf.d /etc/deekayvpn /var/run/sslh /etc/xray > /dev/null 2>&1
echo "$DOMAIN" > /etc/deekayvpn/domain.txt
ssh-keygen -A >/dev/null 2>&1 || true

command -v ss >/dev/null 2>&1 || apt-get install -y iproute2 > /dev/null 2>&1
command -v netfilter-persistent >/dev/null 2>&1 || apt-get install -y netfilter-persistent iptables-persistent > /dev/null 2>&1

if ! systemctl list-unit-files | grep -q "^${STUNNEL_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^stunnel\.service"; then STUNNEL_SERVICE="stunnel"; fi
fi
if ! systemctl list-unit-files | grep -q "^${SQUID_SERVICE}\.service"; then
  if systemctl list-unit-files | grep -q "^squid3\.service"; then SQUID_SERVICE="squid3"; fi
fi

PACKAGE_LIST=(
  neofetch sslh dnsutils stunnel4 squid nano sudo wget unzip tar zip gzip
  iptables iptables-persistent netfilter-persistent bc cron dos2unix whois screen ruby
  apt-transport-https software-properties-common gnupg2 ca-certificates curl net-tools
  nginx haproxy certbot jq figlet git gcc make build-essential perl expect libdbi-perl vnstat socat
  libnet-ssleay-perl libauthen-pam-perl libio-pty-perl apt-show-versions openssh-server rsyslog lsof procps
)

AVAILABLE_PACKAGES=()
for pkg in "${PACKAGE_LIST[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then AVAILABLE_PACKAGES+=("$pkg"); fi
done

SSH_CLIENT_IP="$(echo "${SSH_CONNECTION:-}" | awk '{print $1}')"
if [[ "$SSH_CLIENT_IP" == *:* ]]; then
    echo -e "${CYAN}Tu sesion SSH actual usa IPv6 ($SSH_CLIENT_IP) - se omite deshabilitar IPv6 para no cortar la conexion.${NC}"
else
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null 2>&1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null 2>&1
fi
rm -f /etc/resolv.conf > /dev/null 2>&1
printf 'nameserver %s\nnameserver %s\n' "$Dns_1" "$Dns_2" > /etc/resolv.conf
ln -fs /usr/share/zoneinfo/$MyVPS_Time /etc/localtime > /dev/null 2>&1

cat > /root/.profile <<'EOF_PROFILE'
clear
echo "Script Por Nokasvip"
echo "Escribe 'menu' Para Ver Los Comandos"
EOF_PROFILE

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections > /dev/null 2>&1
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections > /dev/null 2>&1

FAILED_PACKAGES=()
for pkg in "${AVAILABLE_PACKAGES[@]}"; do
    if ! step "Instalando: ${pkg}" apt-get install -y -qq "$pkg"; then FAILED_PACKAGES+=("$pkg"); fi
done

systemctl enable "$SSH_SERVICE" >/dev/null 2>&1 || true
systemctl enable rsyslog >/dev/null 2>&1 || true
systemctl restart rsyslog >/dev/null 2>&1 || true
gem install lolcat >/dev/null 2>&1
apt -y --purge remove apache2 ufw firewalld >/dev/null 2>&1
systemctl stop nginx > /dev/null 2>&1

cat <<'deekay77' > /etc/zorro-luffy
<br><font color="#C12267">HEX TUNNEL | VPN | SERVICE<br></font><br>
<font color="#b3b300"> x No DDOS<br></font>
<font color="#00cc00"> x No Torrent<br></font>
<font color="#ff1aff"> x No Spamming<br></font>
<font color="blue"> x No Phishing<br></font>
<font color="#A810FF"> x No Hacking<br></font><br>
<font color="red">• BROUGHT TO YOU BY <br></font><font color="#00cccc">https://t.me/KYZ_CANAL !<br></font>
deekay77

# OpenSSH
rm -f /etc/ssh/sshd_config > /dev/null 2>&1
cat <<'MySSHConfig' > /etc/ssh/sshd_config
Port myPORT1
Port myPORT2
AddressFamily inet
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
MaxSessions 5000
MaxStartups 500:30:1000
LoginGraceTime 30
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM yes
X11Forwarding yes
PrintMotd no
ClientAliveInterval 120
ClientAliveCountMax 3
UseDNS no
Banner /etc/zorro-luffy
LogLevel QUIET
AcceptEnv LANG LC_*
Subsystem sftp SFTP_SUBSYSTEM
MySSHConfig

sed -i "s|myPORT1|$SSH_Port1|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i "s|myPORT2|$SSH_Port2|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i "s|SFTP_SUBSYSTEM|$SFTP_SUBSYSTEM|g" /etc/ssh/sshd_config > /dev/null 2>&1
sed -i -E '/password\s+(requisite|required)\s+pam_(cracklib|pwquality)\.so.*/d' /etc/pam.d/common-password > /dev/null 2>&1
sed -i 's/use_authtok //g' /etc/pam.d/common-password > /dev/null 2>&1
sed -i '/\/bin\/false/d' /etc/shells > /dev/null 2>&1
sed -i '/\/usr\/sbin\/nologin/d' /etc/shells > /dev/null 2>&1
echo '/bin/false' >> /etc/shells; echo '/usr/sbin/nologin' >> /etc/shells
systemctl restart "$SSH_SERVICE" > /dev/null 2>&1

# SSLH
cd /etc/default/ > /dev/null 2>&1
cat << sslh > /etc/default/sslh
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh --listen 127.0.0.1:$MainPort --ssh 127.0.0.1:$SSH_Port1 --http 127.0.0.1:$WsPort --pidfile /var/run/sslh/sslh.pid"
sslh
mkdir -p /var/run/sslh > /dev/null 2>&1; touch /var/run/sslh/sslh.pid > /dev/null 2>&1; chmod 777 /var/run/sslh/sslh.pid > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1; systemctl enable "$SSLH_SERVICE" > /dev/null 2>&1; systemctl restart "$SSLH_SERVICE" > /dev/null 2>&1
cd > /dev/null 2>&1

StunnelDir=$(ls /etc/default | grep stunnel | head -n1)
cat <<'MyStunnelD' > /etc/default/$StunnelDir
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
BANNER="/etc/zorro-luffy"
PPP_RESTART=0
RLIMITS=""
MyStunnelD

cat <<'MyStunnelC' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
syslog = no
debug = 0
output = /dev/null
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
TIMEOUTclose = 0
[sslh]
accept = Stunnel_Port
connect = 127.0.0.1:MainPort
MyStunnelC

sed -i "s|Stunnel_Port|$Stunnel_Port|g" /etc/stunnel/stunnel.conf > /dev/null 2>&1
sed -i "s|MainPort|$MainPort|g" /etc/stunnel/stunnel.conf > /dev/null 2>&1
systemctl enable "$STUNNEL_SERVICE" > /dev/null 2>&1; systemctl restart "$STUNNEL_SERVICE" > /dev/null 2>&1

loc=/etc/socksproxy; mkdir -p $loc > /dev/null 2>&1; apt-get install -y nodejs > /dev/null 2>&1
cat <<EOF > $loc/proxy.js
const net = require('net');
process.on('uncaughtException', (err) => { console.error('Unhandled Exception:', err); });
const TARGET_HOST = '127.0.0.1'; const TARGET_PORT = $SSH_Port1;
const LISTEN_PORT = parseInt(process.argv[2]);
if (!LISTEN_PORT) { process.exit(1); }
const handleConnection = (clientSocket) => {
    clientSocket.once('data', (data) => {
        const targetSocket = net.connect(TARGET_PORT, TARGET_HOST, () => {
            clientSocket.write('HTTP/1.1 101 <font color="yellow">Hex Tunnel</font>\r\n\r\n');
            clientSocket.pipe(targetSocket); targetSocket.pipe(clientSocket);
        });
        targetSocket.on('error', () => clientSocket.destroy());
        targetSocket.on('close', () => clientSocket.destroy());
    });
    clientSocket.on('error', () => {}); clientSocket.on('close', () => {});
};
const server = net.createServer(handleConnection);
server.listen(LISTEN_PORT, '0.0.0.0', () => { console.log(\`WS Proxy active on isolated port \${LISTEN_PORT}\`); });
EOF

cat <<'service' > /etc/systemd/system/ws-proxy@.service
[Unit]
Description=Node.js WebSocket Proxy on port %i
After=network.target nss-lookup.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/socksproxy
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576
Restart=always
RestartSec=1
ExecStart=/usr/bin/node /etc/socksproxy/proxy.js %i
SyslogIdentifier=ws-proxy-%i
[Install]
WantedBy=multi-user.target
service
systemctl daemon-reload > /dev/null 2>&1
for port in "${WsPorts[@]}"; do systemctl enable ws-proxy@$port > /dev/null 2>&1; systemctl restart ws-proxy@$port > /dev/null 2>&1; done

clear
echo -e "${CYAN}Installing Hiddify-aligned stable Xray Core v26.3.27...${NC}"
XRAY_VER="v26.3.27"

cat <<'EOF_XRAY_INSTALLER' > /usr/local/sbin/xray-install-version
#!/bin/bash
set -o pipefail
umask 077

version="${1:?Usage: xray-install-version VERSION}"
case "$(uname -m)" in
  x86_64|amd64) asset="Xray-linux-64.zip" ;;
  i386|i486|i586|i686) asset="Xray-linux-32.zip" ;;
  aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  armv7l|armv7*) asset="Xray-linux-arm32-v7a.zip" ;;
  *) echo "Unsupported Xray architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp_dir=$(mktemp -d /tmp/xray-install.XXXXXX) || exit 1
trap 'rm -rf "$tmp_dir"' EXIT
base_url="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"

wget -qO "$tmp_dir/xray.zip" "$base_url" 2>/dev/null || { echo "Xray download failed." >&2; exit 1; }
wget -qO "$tmp_dir/xray.zip.dgst" "$base_url.dgst" 2>/dev/null || { echo "Xray digest download failed." >&2; exit 1; }
expected=$(awk -F'= *' 'toupper($1) == "SHA2-256" {print tolower($2); exit}' "$tmp_dir/xray.zip.dgst")
actual=$(sha256sum "$tmp_dir/xray.zip" | awk '{print tolower($1)}')
[ -n "$expected" ] && [ "$actual" = "$expected" ] || { echo "Xray SHA-256 verification failed." >&2; exit 1; }

unzip -q "$tmp_dir/xray.zip" -d "$tmp_dir/unpacked" 2>/dev/null || exit 1
[ -f "$tmp_dir/unpacked/xray" ] || { echo "Xray binary missing from archive." >&2; exit 1; }
chmod 755 "$tmp_dir/unpacked/xray" > /dev/null 2>&1
install -m 755 "$tmp_dir/unpacked/xray" /usr/local/bin/xray.new > /dev/null 2>&1
mv -f /usr/local/bin/xray.new /usr/local/bin/xray > /dev/null 2>&1
EOF_XRAY_INSTALLER
chmod 700 /usr/local/sbin/xray-install-version

if ! step "Instalando V2Ray..." /usr/local/sbin/xray-install-version "$XRAY_VER"; then
  echo -e "${RED}No se pudo instalar una versión verificada de Xray Core ${XRAY_VER}.${NC}"
  exit 1
fi

touch /etc/xray/vless.txt > /dev/null 2>&1; chmod 600 /etc/xray/vless.txt > /dev/null 2>&1

cat <<EOF > /etc/xray/config.json
{
  "log": { "access": "none", "error": "/var/log/xray/error.log", "loglevel": "error" },
  "inbounds": [
    {
      "tag": "vless-tls-dispatcher", "port": 443, "protocol": "vless",
      "settings": {
        "clients": [], "decryption": "none",
        "fallbacks": [
          { "path": "/httpupgrade", "dest": 10005, "xver": 2 },
          { "path": "/vless-tcp", "dest": 10007, "xver": 2 },
          { "path": "/vmess-hup", "dest": 10011, "xver": 2 },
          { "path": "/vmess-tcp", "dest": 10008, "xver": 2 },
          { "path": "/trojan", "dest": 10013, "xver": 2 },
          { "path": "/vless", "dest": 10003, "xver": 2 },
          { "path": "/vmess", "dest": 10009, "xver": 2 },
          { "alpn": "h2", "dest": 10444, "xver": 2 },
          { "dest": 666 }
        ]
      },
      "streamSettings": { "network": "tcp", "security": "tls", "tlsSettings": { "alpn": ["h2", "http/1.1"], "certificates": [ { "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" } ] }, "sockopt": { "tcpFastOpen": true } }
    },
    { "tag": "vless-tcp-http", "listen": "127.0.0.1", "port": 10007, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vless-tcp"] } } }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vless-plain-public", "port": "80,8080,8880,8081", "protocol": "vless", "settings": { "clients": [], "decryption": "none", "fallbacks": [ { "path": "/xhttp", "dest": 10004, "xver": 2 }, { "path": "/vmess-xhttp", "dest": 10010, "xver": 2 }, { "path": "/vless-tcp", "dest": 10007, "xver": 2 }, { "path": "/vmess-tcp", "dest": 10008, "xver": 2 }, { "path": "/vmess-hup", "dest": 10011, "xver": 2 }, { "path": "/vless", "dest": 10003, "xver": 2 }, { "path": "/vmess", "dest": 10009, "xver": 2 }, { "path": "/httpupgrade", "dest": 10005, "xver": 2 }, { "dest": 10080 } ] }, "streamSettings": { "network": "tcp", "security": "none" } },
    { "tag": "vless-ws", "listen": "127.0.0.1", "port": 10003, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vless" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vless-xhttp", "listen": "127.0.0.1", "port": 10004, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "/xhttp", "mode": "auto" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vless-httpupgrade", "listen": "127.0.0.1", "port": 10005, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "security": "none", "httpupgradeSettings": { "path": "/httpupgrade", "host": "" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vless-grpc", "listen": "127.0.0.1", "port": 10006, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "grpc-svc" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vmess-tcp-http", "listen": "127.0.0.1", "port": 10008, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "tcp", "security": "none", "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vmess-tcp"] } } }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vmess-ws", "listen": "127.0.0.1", "port": 10009, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vmess" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vmess-xhttp", "listen": "127.0.0.1", "port": 10010, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "xhttp", "security": "none", "xhttpSettings": { "path": "/vmess-xhttp", "mode": "auto" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vmess-httpupgrade", "listen": "127.0.0.1", "port": 10011, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "httpupgrade", "security": "none", "httpupgradeSettings": { "path": "/vmess-hup", "host": "" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vmess-grpc", "listen": "127.0.0.1", "port": 10012, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "vmess-grpc-svc" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "trojan-ws", "listen": "127.0.0.1", "port": 10013, "protocol": "trojan", "settings": { "clients": [] }, "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/trojan" }, "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true } } },
    { "tag": "vless-grpc-ntls", "port": 8082, "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "grpc-svc" } } },
    { "tag": "vmess-grpc-ntls", "port": 8083, "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "vmess-grpc-svc" } } },
    { "tag": "vless-kcp-ntls", "port": "8084", "protocol": "vless", "settings": { "clients": [], "decryption": "none" }, "streamSettings": { "network": "mkcp", "security": "none", "kcpSettings": { "mtu": 1350, "tti": 20, "uplinkCapacity": 5, "downlinkCapacity": 20, "congestion": false, "readBufferSize": 2, "writeBufferSize": 2 } } },
    { "tag": "vmess-kcp-ntls", "port": "8085", "protocol": "vmess", "settings": { "clients": [] }, "streamSettings": { "network": "mkcp", "security": "none", "kcpSettings": { "mtu": 1350, "tti": 20, "uplinkCapacity": 5, "downlinkCapacity": 20, "congestion": false, "readBufferSize": 2, "writeBufferSize": 2 } } }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} }, { "protocol": "blackhole", "settings": {}, "tag": "blocked" } ]
}
EOF
chmod 600 /etc/xray/config.json > /dev/null 2>&1

mkdir -p /var/log/xray > /dev/null 2>&1
if ! /usr/local/bin/xray run -test -config /etc/xray/config.json > /dev/null 2>&1; then
  echo -e "${RED}Xray configuration validation failed. Review the Xray error printed above.${NC}"
  exit 1
fi

cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1
systemctl disable --now haproxy 2>/dev/null || true
systemctl enable xray > /dev/null 2>&1
systemctl restart xray > /dev/null 2>&1

# USER EXPIRY CRONJOB FOR XRAY
cat <<'EOF_EXP' > /usr/local/bin/exp-check
#!/bin/bash
set -o pipefail
umask 077
now=$(date +%Y-%m-%d)
CONFIG="/etc/xray/config.json"
[ -s "$CONFIG" ] || exit 0

exec 9>/run/lock/xray-config.lock
flock -w 30 9 || { logger -t xray-exp "Timed out waiting for the Xray config lock"; exit 1; }

work_dir=$(mktemp -d /tmp/xray-exp.XXXXXX) || exit 1
trap 'rm -rf "$work_dir"' EXIT

mapfile -t expired_users < <(
  for proto in vless vmess trojan; do
    db="/etc/xray/${proto}.txt"
    [ -f "$db" ] && awk -v d="$now" '$3 < d {print $1}' "$db"
  done | sort -u
)
[ "${#expired_users[@]}" -gt 0 ] || exit 0

expired_json=$(printf '%s\n' "${expired_users[@]}" | jq -R . | jq -s .) || exit 1
jq --argjson expired "$expired_json" '
  (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |=
    map(. as $client | select(($expired | index($client.email)) == null)) |
  (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |=
    map(. as $user | select(($expired | index($user.email)) == null))
' "$CONFIG" > "$work_dir/config.json" || exit 1

if ! /usr/local/bin/xray run -test -config "$work_dir/config.json" >/dev/null 2>&1; then
  logger -t xray-exp "Refusing expiry update: generated Xray config failed validation"
  exit 1
fi

cp -p "$CONFIG" "$work_dir/config.backup" || exit 1
install -m 600 "$work_dir/config.json" "$CONFIG" || exit 1
if ! systemctl restart xray; then
  install -m 600 "$work_dir/config.backup" "$CONFIG"
  systemctl restart xray || true
  logger -t xray-exp "Expiry update rolled back because Xray failed to restart"
  exit 1
fi

for proto in vless vmess trojan; do
  db="/etc/xray/${proto}.txt"
  [ -f "$db" ] || continue
  awk -v d="$now" '$3 >= d {print}' "$db" > "$work_dir/${proto}.txt" || exit 1
  install -m 600 "$work_dir/${proto}.txt" "$db" || exit 1
done
EOF_EXP
chmod +x /usr/local/bin/exp-check > /dev/null 2>&1
echo "0 0 * * * root /usr/local/bin/exp-check >/dev/null 2>&1" > /etc/cron.d/xray-expiry

# Nginx & Squid
rm -rf /home/vps/public_html /etc/nginx/sites-* /etc/nginx/nginx.conf > /dev/null 2>&1; mkdir -p /home/vps/public_html > /dev/null 2>&1
cat <<'myNginxC' > /etc/nginx/nginx.conf
user www-data; worker_processes auto; pid /var/run/nginx.pid;
events { multi_accept on; worker_connections 8192; }
http { gzip on; gzip_vary on; gzip_comp_level 5; gzip_types text/plain application/x-javascript text/xml text/css; autoindex on; sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 65; types_hash_max_size 2048; server_tokens off; include /etc/nginx/mime.types; default_type application/octet-stream; access_log /var/log/nginx/access.log; error_log /var/log/nginx/error.log; client_max_body_size 32M; client_header_buffer_size 8m; large_client_header_buffers 8 8m; fastcgi_buffer_size 8m; fastcgi_buffers 8 8m; fastcgi_read_timeout 600; include /etc/nginx/conf.d/*.conf; }
myNginxC
cat <<'myvpsC' > /etc/nginx/conf.d/vps.conf
server { listen Nginx_Port; server_name 127.0.0.1 localhost; root /home/vps/public_html; location / { try_files $uri $uri/ /index.php?$args; } }
myvpsC
sed -i "s|Nginx_Port|$Nginx_Port|g" /etc/nginx/conf.d/vps.conf > /dev/null 2>&1
systemctl restart "$NGINX_SERVICE" > /dev/null 2>&1

rm -rf /etc/squid/squid.con* > /dev/null 2>&1
cat <<'mySquid' > /etc/squid/squid.conf
acl server dst IP-ADDRESS/32 localhost
acl ports_ port 14 22 53 21 8081 25 8000 3128 443 80 8080 8880 2082 2086 36712
http_port Squid_Port1
http_port Squid_Port2
http_access allow server
http_access deny all
http_access allow all
visible_hostname IP-ADDRESS
mySquid
sed -i "s|IP-ADDRESS|$IPADDR|g" /etc/squid/squid.conf > /dev/null 2>&1; sed -i "s|Squid_Port1|$Squid_Port1|g" /etc/squid/squid.conf > /dev/null 2>&1; sed -i "s|Squid_Port2|$Squid_Port2|g" /etc/squid/squid.conf > /dev/null 2>&1
systemctl restart "$SQUID_SERVICE" > /dev/null 2>&1

# Health Checks
mkdir -p /etc/deekayvpn/health > /dev/null 2>&1
cat <<'ServiceChecker' > /etc/deekayvpn/service_checker.sh
#!/bin/bash
MYID="MYCHATID"; KEY="MYBOTID"; URL="https://api.telegram.org/bot${KEY}/sendMessage"
send_telegram_message() { curl -s --max-time 10 --retry 5 --retry-delay 2 --retry-max-time 10 -d "chat_id=${MYID}&text=$1&disable_web_page_preview=true&parse_mode=markdown" "${URL}" >/dev/null 2>&1; }
server_ip="IPADDRESS"; datenow=$(date +"%Y-%m-%d %T"); IPCOUNTRY=$(curl -s "https://freeipapi.com/api/json/${server_ip}" | jq -r '.countryName')
STATE_DIR="/etc/deekayvpn/health"
check_port() { ss -lnt | awk '{print $4}' | grep -q ":$1$"; }
mark_fail() { local f="$STATE_DIR/$1.fail"; local n=0; [ -f "$f" ] && n=$(cat "$f"); n=$((n+1)); echo "$n" > "$f"; echo "$n"; }
clear_fail() { rm -f "$STATE_DIR/$1.fail"; }
restart_after_3_fails() {
    local fails=$(mark_fail "$1")
    if [ "$fails" -ge 3 ]; then
        systemctl restart "$2" >/dev/null 2>&1
        send_telegram_message "Service *$2* was offline or missing port(s) *$3* on server *${IPCOUNTRY}* ($server_ip). It has been auto-restarted at *${datenow}*."
        clear_fail "$1"
    fi
}
if check_port SSHPORT1 && check_port SSHPORT2 && systemctl is-active --quiet ssh; then clear_fail ssh; else restart_after_3_fails ssh ssh "SSHPORT1,SSHPORT2"; fi
if check_port STUNNELPORT && systemctl is-active --quiet stunnel4; then clear_fail stunnel4; else restart_after_3_fails stunnel4 stunnel4 "STUNNELPORT"; fi
if check_port SSLHPORT && systemctl is-active --quiet sslh; then clear_fail sslh; else restart_after_3_fails sslh sslh "SSLHPORT"; fi
if check_port SQUIDPORT1 && check_port SQUIDPORT2 && systemctl is-active --quiet squid; then clear_fail squid; else restart_after_3_fails squid squid "SQUIDPORT1,SQUIDPORT2"; fi
if check_port NGINXPORT && systemctl is-active --quiet nginx; then clear_fail nginx; else restart_after_3_fails nginx nginx "NGINXPORT"; fi
for port in 10080 25 2082 2086; do if check_port $port && systemctl is-active --quiet ws-proxy@$port; then clear_fail ws-proxy-$port; else restart_after_3_fails ws-proxy-$port ws-proxy@$port "$port"; fi; done
if check_port 443 && systemctl is-active --quiet xray; then clear_fail xray; else restart_after_3_fails xray xray "443, 80"; fi
if systemctl is-active --quiet hysteria-server; then clear_fail hysteria-server; else restart_after_3_fails hysteria-server hysteria-server "UDP"; fi
ServiceChecker

chmod 755 /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|MYCHATID|$My_Chat_ID|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|MYBOTID|$My_Bot_Key|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|IPADDRESS|$IPADDR|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|STUNNELPORT|$Stunnel_Port_Num|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSLHPORT|$MainPort|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SQUIDPORT1|$Squid_Port1|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SQUIDPORT2|$Squid_Port2|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|NGINXPORT|$Nginx_Port|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSHPORT1|$SSH_Port1|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1
sed -i "s|SSHPORT2|$SSH_Port2|g" /etc/deekayvpn/service_checker.sh > /dev/null 2>&1

echo "*/3 * * * * root /bin/bash /etc/deekayvpn/service_checker.sh >/dev/null 2>&1" > /etc/cron.d/service-checker

mkdir -p /etc/deekayvpn > /dev/null 2>&1
touch /etc/deekayvpn/ssh_limits.txt > /dev/null 2>&1
cat <<'SSHLimitChecker' > /etc/deekayvpn/ssh_limit_checker.sh
#!/bin/bash
DB="/etc/deekayvpn/ssh_limits.txt"
[ -s "$DB" ] || exit 0
while read -r suser slimit; do
  [ -z "$suser" ] && continue
  [[ "$slimit" =~ ^[0-9]+$ ]] || continue
  [ "$slimit" -le 0 ] && continue
  id "$suser" >/dev/null 2>&1 || continue
  mapfile -t sessions < <(ps -u "$suser" -o pid=,etimes=,cmd= 2>/dev/null | awk '$0 ~ /sshd/ {print $1" "$2}')
  count=${#sessions[@]}
  [ "$count" -le "$slimit" ] && continue
  excess=$((count - slimit))
  mapfile -t sorted < <(printf '%s\n' "${sessions[@]}" | sort -k2,2n)
  for ((i=0; i<excess; i++)); do
    pid=$(awk '{print $1}' <<< "${sorted[$i]}")
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
done < "$DB"
SSHLimitChecker
chmod 755 /etc/deekayvpn/ssh_limit_checker.sh > /dev/null 2>&1
echo "* * * * * root /bin/bash /etc/deekayvpn/ssh_limit_checker.sh >/dev/null 2>&1" > /etc/cron.d/ssh-limit-checker
rm -f /etc/logrotate.d/rsyslog > /dev/null 2>&1
cat <<'logrotate' > /etc/logrotate.d/rsyslog
/var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/xray/access.log /var/log/xray/error.log { rotate 7; daily; missingok; notifempty; compress; delaycompress; sharedscripts; postrotate; /usr/lib/rsyslog/rsyslog-rotate; endscript; }
logrotate
chown root:root /var/log > /dev/null 2>&1; chmod 755 /var/log > /dev/null 2>&1; chown syslog:adm /var/log/syslog > /dev/null 2>&1; chmod 640 /var/log/syslog > /dev/null 2>&1
echo "*/5 * * * * root /usr/sbin/logrotate -v -f /etc/logrotate.d/rsyslog >/dev/null 2>&1" > /etc/cron.d/logrotate
echo "0 3 * * * root sync; echo 3 > /proc/sys/vm/drop_caches" > /etc/cron.d/drop-cache

# ==========================================
# AGGRESSIVE SYSTEM & CONNTRACK TUNING
# ==========================================
modprobe nf_conntrack 2>/dev/null || true; echo "nf_conntrack" > /etc/modules-load.d/freenet.conf
cat <<'SYSCTL' > /etc/sysctl.d/99-freenet-tuning.conf
fs.file-max = 1048576
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_udp_timeout = 60
SYSCTL
sysctl --system > /dev/null 2>&1 || true
mkdir -p /etc/security/limits.d > /dev/null 2>&1
cat <<'LIMITS' > /etc/security/limits.d/99-freenet.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

# SLOWDNS
rm -rf /etc/slowdns > /dev/null 2>&1; mkdir -m 777 /etc/slowdns > /dev/null 2>&1
cat > /etc/slowdns/server.key << END
$Serverkey
END
cat > /etc/slowdns/server.pub << END
$Serverpub
END
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server" 2>/dev/null
chmod +x /etc/slowdns/server.key /etc/slowdns/server.pub /etc/slowdns/sldns-server > /dev/null 2>&1
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT > /dev/null 2>&1
cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
ExecStart=/etc/slowdns/sldns-server -udp :53 -privkey-file /etc/slowdns/server.key $Nameserver 127.0.0.1:$SSH_Port2
Restart=on-failure
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload > /dev/null 2>&1; systemctl enable server-sldns > /dev/null 2>&1; systemctl restart server-sldns > /dev/null 2>&1

# ==========================================
# CONFIGURACIÓN TFN-UDP (ESTILO ORIGINAL Y SOCKET)
# ==========================================
instalar_tfn_udp() {
    local DOMAIN_UDP="${DOMAIN}"
    local PROTOCOL="udp"
    local UDP_PORT=":36712"
    local CONFIG_DIR="/etc/hysteria"
    local CONFIG_FILE="$CONFIG_DIR/config.json"
    local EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
    local SYSTEMD_SERVICES_DIR="/etc/systemd/system"
    local REPO_URL="https://github.com/apernet/hysteria"

    echo "Configurando entorno TFN-UDP puro con obfs socket..."
    mkdir -p "$CONFIG_DIR"
    
    # Generar config.json nativo de TFN-UDP sin requerir auth compleja
    cat << EOF > "$CONFIG_FILE"
{
  "server": "$DOMAIN_UDP",
  "listen": "$UDP_PORT",
  "protocol": "$PROTOCOL",
  "cert": "/etc/xray/xray.crt",
  "key": "/etc/xray/xray.key",
  "up": "100 Mbps",
  "up_mbps": 100,
  "down": "100 Mbps",
  "down_mbps": 100,
  "disable_udp": false,
  "insecure": true,
  "obfs": "$OBFS"
}
EOF

    echo "Descargando binario Hysteria TFN-UDP (v1.3.5)..."
    local _arch="amd64"
    if [[ "$(uname -m)" == "aarch64" ]]; then _arch="arm64"; fi
    curl -R -H 'Cache-Control: no-cache' -L "$REPO_URL/releases/download/v1.3.5/hysteria-linux-$_arch" -o "$EXECUTABLE_INSTALL_PATH"
    chmod +x "$EXECUTABLE_INSTALL_PATH"

    echo "Configurando Servicio TFN-UDP..."
    cat << EOF > "$SYSTEMD_SERVICES_DIR/hysteria-server.service"
[Unit]
Description=TFN-UDP Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/etc/hysteria
Environment="PATH=/usr/local/bin/hysteria"
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.json

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria-server.service
    systemctl start hysteria-server.service

    echo "Configurando reglas de red IPTables (10000:65000) para UDP..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1
    IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    sysctl -w net.ipv4.conf.$IFACE.rp_filter=0 >/dev/null 2>&1
    
    iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
    ip6tables -t nat -A PREROUTING -i $IFACE -p udp --dport 10000:65000 -j DNAT --to-destination $UDP_PORT
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
}

step "Instalando y Configurando núcleo TFN-UDP..." instalar_tfn_udp

# Creating startup script
cat <<'deekayz' > /etc/deekaystartup
#!/bin/sh
ln -fs /usr/share/zoneinfo/MyTimeZone /etc/localtime
export DEBIAN_FRONTEND=noninteractive
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo "nameserver DNS1" > /etc/resolv.conf; echo "nameserver DNS2" >> /etc/resolv.conf
mkdir -p /var/run/sslh; touch /var/run/sslh/sslh.pid; chmod 777 /var/run/sslh/sslh.pid

iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -t nat -C PREROUTING -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 53 -j ACCEPT
iptables -t nat -C PREROUTING -p udp --dport 443 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 443 -j ACCEPT
deekayz

sed -i "s|MyTimeZone|$MyVPS_Time|g" /etc/deekaystartup > /dev/null 2>&1
sed -i "s|DNS1|$Dns_1|g" /etc/deekaystartup > /dev/null 2>&1
sed -i "s|DNS2|$Dns_2|g" /etc/deekaystartup > /dev/null 2>&1

cat <<'deekayx' > /etc/systemd/system/deekaystartup.service
[Unit]
Description=Custom startup script
ConditionPathExists=/etc/deekaystartup
[Service]
Type=oneshot
ExecStart=/etc/deekaystartup
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
deekayx
chmod +x /etc/deekaystartup > /dev/null 2>&1; systemctl enable deekaystartup > /dev/null 2>&1

# VNSTAT INITIALIZATION
IFACE="$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)"
vnstat -u -i "$IFACE" 2>/dev/null || true
systemctl enable vnstat > /dev/null 2>&1
systemctl restart vnstat > /dev/null 2>&1

# MENU CREATION (Estética Nokasvip intacta)
mkdir -p /usr/local/bin > /dev/null 2>&1
sed -i '/# KYZTUNNEL_MENU_AUTOSTART_START/,/# KYZTUNNEL_MENU_AUTOSTART_END/d' ~/.bashrc 2>/dev/null || true
cat >> ~/.bashrc <<'EOF_BASHRC_AUTOSTART'
# KYZTUNNEL_MENU_AUTOSTART_START
if [[ $- == *i* ]] && [ -z "$KYZTUNNEL_MENU_SHOWN" ]; then
    export KYZTUNNEL_MENU_SHOWN=1
    menu
fi
# KYZTUNNEL_MENU_AUTOSTART_END
EOF_BASHRC_AUTOSTART

cat > /usr/local/bin/menu <<'EOF_MENU'
#!/bin/bash

# Modern Color Palette
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'
BG_TITLE='\033[48;5;25m\033[97m\033[1m'
ACC='\033[38;5;44m'

DOMAIN=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || curl -4 -s --max-time 2 ipv4.icanhazip.com)
SSH_LIMIT_DB="/etc/deekayvpn/ssh_limits.txt"
mkdir -p /etc/deekayvpn 2>/dev/null || true
touch "$SSH_LIMIT_DB" 2>/dev/null || true

if [ -f /etc/xray/cert_type ] && grep -q "letsencrypt" /etc/xray/cert_type; then XRAY_INSECURE="0"
else XRAY_INSECURE="1"; fi
[ "$XRAY_INSECURE" = "1" ] && INSECURE_PARAM="&allowInsecure=1" || INSECURE_PARAM=""

server_ip() { curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'; }
cpu_count() { nproc 2>/dev/null || echo "1"; }
ram_percent() { free 2>/dev/null | awk '/Mem:/ { if ($2>0) printf "%.1f%%", ($3/$2)*100; else print "0.0%" }'; }
cpu_percent() { top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ { gsub("%us","",$1); gsub(" ","",$1); split($1,a,":"); if (a[2] == "") print "0.0%"; else printf "%.1f%%", a[2]+0 }'; }
buffer_mem() { free -m 2>/dev/null | awk '/Mem:/ {print $6 "M"}'; }

server_status() {
  local ok=0
  for s in ssh stunnel4 squid nginx server-sldns hysteria-server ws-proxy@10080 xray; do
    systemctl is-active --quiet "$s" 2>/dev/null && ok=$((ok+1))
  done
  [ "$ok" -ge 4 ] && echo -e "${GREEN}EN LÍNEA${NC}" || echo -e "${RED}PROBLEMAS DETECTADOS${NC}"
}
pause_return() { echo; read -rp "Presiona ENTER para volver... " _; }

# --- FUNCIONES XRAY ---
add_xray() {
  clear
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "                   ${BOLD}CREAR CUENTA XRAY${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e " [1] VLESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [2] VMESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
  echo -e " [3] TROJAN (TLS)"
  echo -e " [4] TODO-EN-UNO (VLESS + VMESS + TROJAN)"
  read -rp " Selecciona Protocolo: " prot
  read -rp " Nombre de usuario: " user
  
  if grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
    echo -e "${RED}¡El nombre de usuario ya existe!${NC}"; pause_return; return
  fi

  read -rp " Validez (Días): " masa
  exp=$(date -d "+${masa} days" +"%Y-%m-%d")

  read -rp " ¿Quieres usar un UUID personalizado? (y/N): " custom_uuid_prompt
  if [[ "$custom_uuid_prompt" =~ ^[Yy]$ ]]; then read -rp " Ingresa el UUID personalizado: " uuid
  else uuid=$(cat /proc/sys/kernel/random/uuid); fi

  pass="KyzTunnel${uuid:0:6}"
  
  VLESS_TAGS='["vless-tls-dispatcher","vless-tcp-http","vless-plain-public","vless-ws","vless-xhttp","vless-httpupgrade","vless-grpc","vless-grpc-ntls","vless-kcp-ntls"]'
  VMESS_TAGS='["vmess-tcp-http","vmess-ws","vmess-xhttp","vmess-httpupgrade","vmess-grpc","vmess-grpc-ntls","vmess-kcp-ntls"]'
  TROJAN_TAGS='["trojan-ws"]'

  if [ "$prot" == "1" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VLESS_TAGS" '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]' /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    
    clear; echo -e "${GREEN}CUENTA VLESS CREADA${NC}\nUsuario: $user\nExpira: $exp"
    echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\nWS: vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS"
  
  elif [ "$prot" == "2" ]; then
    jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VMESS_TAGS" '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]' /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    
    clear; echo -e "${GREEN}CUENTA VMESS CREADA${NC}\nUsuario: $user\nExpira: $exp"
    VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
    echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}\nWS: vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
  
  elif [ "$prot" == "3" ]; then
    jq --arg pass "$pass" --arg user "$user" --argjson tags "$TROJAN_TAGS" '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $pass $exp" >> /etc/xray/trojan.txt
    
    clear; echo -e "${GREEN}CUENTA TROJAN CREADA${NC}\nUsuario: $user\nContraseña: $pass\nExpira: $exp"
    echo -e "\n${YELLOW}TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"

  elif [ "$prot" == "4" ]; then
    jq --arg uuid "$uuid" --arg pass "$pass" --arg user "$user" --argjson vtags "$VLESS_TAGS" --argjson mtags "$VMESS_TAGS" --argjson ttags "$TROJAN_TAGS" '(.inbounds[] | select(.tag as $t | $vtags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}] | (.inbounds[] | select(.tag as $t | $mtags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}] | (.inbounds[] | select(.tag as $t | $ttags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    echo "$user $uuid $exp" >> /etc/xray/vless.txt
    echo "$user $uuid $exp" >> /etc/xray/vmess.txt
    echo "$user $pass $exp" >> /etc/xray/trojan.txt
    clear; echo -e "${GREEN}CUENTA TODO-EN-UNO CREADA${NC}\nUsuario: $user\nExpira: $exp"
  fi
  systemctl restart xray; pause_return
}

del_xray() {
  clear; echo -e "${RED}ELIMINAR CUENTA XRAY${NC}"
  mapfile -t users < <(cat /etc/xray/*.txt 2>/dev/null | awk '{print $1}' | sort -u)
  if [ ${#users[@]} -eq 0 ]; then echo -e "${YELLOW}No se encontraron usuarios de Xray.${NC}"; pause_return; return; fi
  for i in "${!users[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${users[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"
  read -rp "  Selecciona usuario a eliminar: " idx
  if [[ "$idx" == "00" || "$idx" == "0" ]]; then return; fi
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -le 0 ] || [ "$idx" -gt "${#users[@]}" ]; then echo -e "${RED}Selección inválida.${NC}"; pause_return; return; fi
  user="${users[$((idx-1))]}"
  jq "(.inbounds[].settings.clients) |= map(select(.email != \"$user\"))" /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
  sed -i "/^$user /d" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null
  systemctl restart xray
  echo -e "\n${GREEN}✔ Usuario $user eliminado exitosamente.${NC}"; pause_return
}

renew_xray() {
  clear; echo -e "${CYAN}RENOVAR CUENTA XRAY${NC}"
  read -rp " Usuario a renovar: " user
  if ! grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then echo -e "${RED}Usuario no encontrado.${NC}"; pause_return; return; fi
  read -rp " Días a Agregar: " days
  for proto in vless vmess trojan; do 
    if grep -qw "^$user" "/etc/xray/${proto}.txt"; then
      current_exp=$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $3}')
      new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
      sed -i "s/^$user .* $current_exp/$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $1 " " $2}') $new_exp/" "/etc/xray/${proto}.txt"
    fi
  done
  echo -e "\n${GREEN}✔ Usuario '$user' renovado exitosamente.${NC}\nNueva Expiración: $new_exp"; pause_return
}

# --- FUNCIONES SSH / UNIFICADAS ---
list_real_users() { awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null; }
select_user() {
  local purpose="$1"; mapfile -t USERS < <(list_real_users)
  if [ "${#USERS[@]}" -eq 0 ]; then echo -e "${RED}No se encontraron cuentas de usuario activas.${NC}"; return 1; fi
  clear; printf " %-56s \n" "${BOLD}$purpose${NC}"
  for i in "${!USERS[@]}"; do printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${USERS[$i]}"; done
  echo -e "\n  [${YELLOW}00${NC}] Atrás\n"
  read -rp "  Selecciona un número de cuenta: " idx
  [[ "$idx" == "00" || "$idx" == "0" ]] && return 1
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#USERS[@]}" ]; then echo -e "${RED}  Selección inválida.${NC}"; return 1; fi
  SELECTED_USER="${USERS[$((idx-1))]}"; return 0
}

create_user() {
  clear; echo -e "${CYAN}CREAR NUEVO USUARIO SSH/UDP/SlowDNS${NC}"
  read -rp "  Nombre de usuario: " user
  [ -z "$user" ] && return
  read -rp "  Contraseña: " pass
  [ -z "$pass" ] && return
  read -rp "  Válido por (días): " days
  read -rp "  Límite de conexiones simultáneas (0 = sin límite): " conn_limit
  [ -z "$conn_limit" ] && conn_limit=0

  useradd --badname -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>/dev/null
  echo "$user:$pass" | chpasswd
  sed -i "/^$user /d" "$SSH_LIMIT_DB" 2>/dev/null
  if [ "$conn_limit" -gt 0 ]; then echo "$user $conn_limit" >> "$SSH_LIMIT_DB"; fi

  IP=$(curl -s ipv4.icanhazip.com)
  clear; echo -e "${GREEN}CUENTA CREADA EXITOSAMENTE${NC}"
  echo -e "  Dominio: $DOMAIN\n  IP: $IP\n  Usuario: $user\n  Pass: $pass\n  Expira: $(date -d "+$days days" +%Y-%m-%d)"
  echo -e "  ${YELLOW}✔ Servicios Activados:${NC} SSH, WebSocket, SlowDNS, TFN-UDP Libre (36712)"
  pause_return
}

delete_user() {
  if ! select_user "DELETE SSH/UDP USER"; then pause_return; return; fi
  clear; read -rp "¿Eliminar usuario $SELECTED_USER de todos los servicios? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    pkill -u "$SELECTED_USER" 2>/dev/null
    if userdel -r -f "$SELECTED_USER" 2>/dev/null || userdel -f "$SELECTED_USER" 2>/dev/null; then
        sed -i "/^$SELECTED_USER /d" "$SSH_LIMIT_DB" 2>/dev/null
        echo -e "${GREEN}El usuario $SELECTED_USER ha sido eliminado de forma global.${NC}"
    fi
  fi
  pause_return
}

extend_user() {
  if ! select_user "EXTEND USER EXPIRY"; then pause_return; return; fi
  clear; read -rp "Ingresa número de días a agregar para $SELECTED_USER: " days
  current=$(chage -l "$SELECTED_USER" 2>/dev/null | awk -F": " '/Account expires/ {print $2}')
  if [ "$current" = "never" ] || [ -z "$current" ]; then new_exp=$(date -d "+$days days" +%Y-%m-%d)
  else new_exp=$(date -d "$current +$days days" +%Y-%m-%d); fi
  chage -E "$new_exp" "$SELECTED_USER"
  echo -e "${GREEN}¡Éxito! Cuenta extendida.\nNueva Expiración: $new_exp${NC}"; pause_return
}

draw_item() { printf "${ACC}║${NC}  ${WHITE}[${YELLOW}%s${WHITE}]${NC} %-56s${ACC}║${NC}\n" "$1" "$2"; }
draw_header() {
  local os_name=$(. /etc/os-release 2>/dev/null; echo "${ID:-UNKNOWN}" | tr '[:lower:]' '[:upper:]')
  local os_ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
  local os="${os_name} ${os_ver}"
  local arch=$(uname -m)
  local cores=$(cpu_count)
  local ip=$(server_ip)
  local time=$(date '+%H:%M %Z')
  local status=$(server_status)
  local ram=$(ram_percent)
  local cpu=$(cpu_percent)
  local buf=$(buffer_mem)

  echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf "${ACC}║${NC}${BG_TITLE}   🐉  Kyz Auto  ✸  Por Nokasvip  🐉%-25s${NC}${ACC}║${NC}\n" ""
  echo -e "${ACC}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf "${ACC}║${NC}  ${DIM}OS:${NC}    ${WHITE}%-17s${NC} ${DIM}Arch:${NC} ${WHITE}%-11s${NC} ${DIM}Cores:${NC} ${WHITE}%-10s${NC}${ACC}║${NC}\n" "$os" "$arch" "$cores"
  printf "${ACC}║${NC}  ${DIM}IP:${NC}    ${WHITE}%-17s${NC} ${DIM}Hora:${NC} ${WHITE}%-11s${NC} ${DIM}Estado:${NC} ${GREEN}%-9s${NC}${ACC}║${NC}\n" "$ip" "$time" "$status"
  echo -e "${ACC}╠────────────────────── ${BOLD}Puertos Abiertos${NC} ${ACC}──────────────────────╣${NC}"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "SSH:" "22, 299" "System-DNS:" "53"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "WEB-Nginx:" "85" "SSL:" "443"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "XRAY TLS:" "443" "SlowDNS:" "53"
  printf "${ACC}║${NC}  ${WHITE}• %-12s${NC}${GREEN}%-14s${NC}${ACC} │ ${NC}${WHITE}• %-12s${NC}${GREEN}%-15s${NC}${ACC}║${NC}\n" "TFN-UDP:" "36712" "SOCKS:" "127.0.0.1:1080"
  echo -e "${ACC}╠──────────────────── ${BOLD}Recursos Del Sistema${NC} ${ACC}────────────────────╣${NC}"
  printf "${ACC}║${NC}  ${DIM}RAM:${NC} ${YELLOW}%-14s${NC} ${DIM}CPU:${NC} ${YELLOW}%-10s${NC} ${DIM}Buffer:${NC} ${YELLOW}%-16s${NC}${ACC}║${NC}\n" "$ram" "$cpu" "$buf"
  echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
}
while true; do
  clear; draw_header; echo
  echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "01" "Cuentas SSH/UDP/SlowDNS" "02" "Cuentas Xray (V2ray)"
  printf "${ACC}║${NC}  ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}│${NC} ${YELLOW}%-2s${NC} ${WHITE}%-26s${NC}${ACC}║${NC}\n" "03" "Reiniciar Servidor" "00" "Salir"
  echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ${WHITE}Selecciona una opción:${NC} ")" opt
  case "$opt" in
    1|01) 
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠────────────${NC} ${BOLD}GESTIÓN DE CUENTAS SSH/UDP/SlowDNS${NC} ${ACC}────────────╣${NC}"
        draw_item "1" "Crear Usuario unificado"
        draw_item "2" "Extender Expiración"
        draw_item "3" "Eliminar Usuario unificado"
        draw_item "4" "Listar Todas Las Cuentas"
        draw_item "0" "Atrás"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) create_user;; 2) extend_user;; 3) delete_user;; 4) list_real_users | nl -w2 -s'. '; pause_return;; 0) break;; esac
      done ;;
    2|02) 
      while true; do
        clear
        echo -e "${ACC}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${ACC}╠──────────────────${NC} ${BOLD}GESTIÓN DE CUENTAS XRAY${NC} ${ACC}───────────────────╣${NC}"
        draw_item "1" "Agregar Cuenta Xray"
        draw_item "2" "Renovar Cuenta Xray"
        draw_item "3" "Eliminar Cuenta Xray"
        draw_item "0" "Atrás"
        echo -e "${ACC}╚══════════════════════════════════════════════════════════════╝${NC}"
        read -rp "$(echo -e "  ${BG_TITLE} ► ${NC} ")" sub; case "$sub" in 1) add_xray;; 2) renew_xray;; 3) del_xray;; 0) break;; esac
      done ;;
    3|03) clear; read -rp "¿Reiniciar el servidor ahora? [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]] && reboot ;;
    0|00) clear; exit 0 ;;
  esac
done
EOF_MENU

sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" /usr/local/bin/menu > /dev/null 2>&1
chmod +x /usr/local/bin/menu > /dev/null 2>&1
cp /usr/local/bin/menu /usr/bin/menu > /dev/null 2>&1
cp /usr/local/bin/menu /usr/bin/Menu > /dev/null 2>&1

# LET'S ENCRYPT RENEWAL HOOK
if [ "$USE_LETSENCRYPT" = true ]; then
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy > /dev/null 2>&1
    cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh > /dev/null 2>&1
    echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hex-tunnel.sh" > /etc/cron.d/certbot-renew
fi

# Finishing
chown -R www-data:www-data /home/vps/public_html > /dev/null 2>&1
clear
figlet Kyz Auto Script By Nokasvip -c | lolcat 2>/dev/null
echo -e "${GREEN}       ¡Instalación Completa! El sistema necesita reiniciarse para aplicar todos los cambios! ${NC}"
history -c > /dev/null 2>&1; rm /root/full.sh 2>/dev/null || true
echo -e "${CYAN}           ¡El servidor se reiniciará en 10 segundos! ${NC}"
sleep 10
reboot