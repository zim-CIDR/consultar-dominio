#!/usr/bin/env bash
# 🧠 Cyberpunk RDAP Lookup — Feito por Will
# Consulta RDAP oficial e exibe resultado no estilo cyberpunk neon
# Auto-instalação de dependências: curl, jq e iputils-ping (ou ping)

# Cores neon
CYAN="\e[96m"
MAGENTA="\e[95m"
GREEN="\e[92m"
RED="\e[91m"
YELLOW="\e[93m"
RESET="\e[0m"

banner()
{
  echo -e "${MAGENTA}"
  echo "───────────────────────────────────────────"
  echo "   🧠 CYBERPUNK RDAP LOOKUP by Will"
  echo "───────────────────────────────────────────"
  echo -e "${RESET}"
}

check_install()
{
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${YELLOW}⚡ $cmd não encontrado. Tentando instalar...${RESET}"
    if command -v apt &>/dev/null; then
      sudo apt update && sudo apt install -y "$pkg"
    elif command -v yum &>/dev/null; then
      sudo yum install -y "$pkg"
    elif command -v pacman &>/dev/null; then
      sudo pacman -Sy --noconfirm "$pkg"
    else
      echo -e "${RED}❌ Não foi possível instalar $pkg automaticamente. Instale manualmente.${RESET}"
      exit 1
    fi
  fi
}

# Verifica dependências
check_install curl curl
check_install jq jq
# Verifica se o 'ping' está disponível (em alguns sistemas, o pacote é iputils-ping)
if ! command -v ping &>/dev/null; then
    echo -e "${YELLOW}⚡ ping não encontrado. Tentando instalar iputils-ping...${RESET}"
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y iputils-ping
    elif command -v yum &>/dev/null; then
        sudo yum install -y iputils-ping
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm iputils-ping
    else
        echo -e "${RED}❌ Não foi possível instalar ping. Instale manualmente o 'ping' ou 'iputils-ping'.${RESET}"
        exit 1
    fi
fi


# Nova função para verificar status e obter IP
check_online_and_get_ip()
{
  local dominio="$1"
  local ip_resolvido

  # Tenta resolver o IP primeiro
  ip_resolvido=$(dig +short "$dominio" | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n 1)

  if [[ -z "$ip_resolvido" ]]; then
    echo -e "${RED}🌐 Endereço:${RESET} ${RED}OFFLINE (Sem resolução de IP)${RESET}"
    echo -e "${CYAN}📡 IP:${RESET} ${RED}N/A${RESET}"
    return 1 # Endereço não resolveu
  fi

  echo -e "${CYAN}📡 IP:${RESET} $ip_resolvido"

  # Tenta dar 1 ping para verificar se está online
  if ping -c 1 -W 1 "$ip_resolvido" &>/dev/null; then
    echo -e "${GREEN}🌐 Endereço:${RESET} ${GREEN}ONLINE${RESET}"
    return 0 # Endereço online
  else
    # O IP resolveu, mas não respondeu ao ping
    echo -e "${YELLOW}🌐 Endereço:${RESET} ${YELLOW}OFFLINE (IP não responde a ping)${RESET}"
    return 1 # Endereço offline
  fi
}


consulta_rdap()
{
  local dominio="$1"

  if [[ -z "$dominio" ]]; then
    echo -e "${RED}⚠️  Digite um domínio para consultar.${RESET}"
    return 1
  fi

  # 1. VERIFICA STATUS E MOSTRA IP
  echo -e "\n${YELLOW}⚡ Verificando status e resolvendo IP...${RESET}"
  # Executa a nova função, mas ignora o código de retorno para garantir que o RDAP seja consultado,
  # mesmo que esteja offline (o RDAP é útil de qualquer forma).
  check_online_and_get_ip "$dominio"

  # 2. CONSULTA RDAP
  echo -e "\n${YELLOW}⏳ Consultando RDAP / ICANN para: ${CYAN}${dominio}${RESET}"
  local tld="${dominio##*.}"

  if [[ "$tld" == "br" ]]; then
    local url="https://rdap.registro.br/domain/${dominio}"
    local data
    data=$(curl -s "$url")

    if [[ -z "$data" || "$(echo "$data" | jq -r '.errorCode // empty')" != "" ]]; then
      echo -e "${RED}❌ Domínio não encontrado no Registro.br${RESET}"
      return 1
    fi

    local registrar owner email criacao atualizacao expiracao
    registrar=$(echo "$data" | jq -r '.registrar.name // "Registro.br"')
    criacao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="registration") | .eventDate' 2>/dev/null)
    atualizacao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="last changed") | .eventDate' 2>/dev/null)
    expiracao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="expiration") | .eventDate' 2>/dev/null)
    owner=$(echo "$data" | jq -r '.entities[]?.vcardArray[1][]? | select(.[0]=="fn") | .[3]' | head -n1)
    email=$(echo "$data" | jq -r '.entities[]?.vcardArray[1][]? | select(.[0]=="email") | .[3]' | head -n1)

    echo -e "\n${MAGENTA}⚡ Dados RDAP (.BR)${RESET}"
    echo "───────────────────────────────────────────"
    echo -e "${CYAN}🌐 Domínio:${RESET} $dominio"
    echo -e "${CYAN}👤 Titular:${RESET} ${owner:-(oculto)}"
    echo -e "${CYAN}📧 E-mail:${RESET} ${email:-(não disponível)}"
    echo -e "${CYAN}🏢 Registrar:${RESET} $registrar"
    echo -e "${CYAN}📅 Criado em:${RESET} ${criacao:-—}"
    echo -e "${CYAN}♻️ Atualizado em:${RESET} ${atualizacao:-—}"
    echo -e "${CYAN}⏳ Expira em:${RESET} ${expiracao:-—}"
    echo -e "${CYAN}📡 Nameservers:${RESET}"
    echo "$data" | jq -r '.nameservers[]?.ldhName' | sed "s/^/   - /"
    return 0
  fi

  # --- Outros TLDs ---
  local bootstrap="https://data.iana.org/rdap/dns.json"
  local rdap_server
  rdap_server=$(curl -s "$bootstrap" | jq -r ".services[] | select(.[0][] | contains(\".${tld}\")) | .[1][0]" | head -n1)

  if [[ -z "$rdap_server" || "$rdap_server" == "null" ]]; then
    echo -e "${RED}❌ Nenhum servidor RDAP encontrado para .${tld}${RESET}"
    return 1
  fi

  local data
  data=$(curl -s "${rdap_server}/domain/${dominio}")

  if [[ -z "$data" || "$(echo "$data" | jq -r '.errorCode // empty')" != "" ]]; then
    echo -e "${RED}❌ Domínio não encontrado no servidor RDAP${RESET}"
    return 1
  fi

  local registrar owner email criacao atualizacao expiracao
  registrar=$(echo "$data" | jq -r '.registrar.name // "Não informado"')
  criacao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="registration") | .eventDate' 2>/dev/null)
  atualizacao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="last changed") | .eventDate' 2>/dev/null)
  expiracao=$(echo "$data" | jq -r '.events[]? | select(.eventAction=="expiration") | .eventDate' 2>/dev/null)
  owner=$(echo "$data" | jq -r '.entities[]? | select(.roles[]? | test("registrant|administrative|technical";"i")) | .vcardArray[1][]? | select(.[0]=="fn") | .[3]' | head -n1)
  email=$(echo "$data" | jq -r '.entities[]? | select(.roles[]? | test("registrant|administrative|technical";"i")) | .vcardArray[1][]? | select(.[0]=="email") | .[3]' | head -n1)

  if [[ -z "$email" || "$email" == "null" ]]; then
    email=$(echo "$data" | jq -r '.entities[]? | select(.roles[]? | test("abuse";"i")) | .vcardArray[1][]? | select(.[0]=="email") | .[3]' | head -n1)
  fi

  echo -e "\n${MAGENTA}⚡ Dados RDAP (TLD Internacional)${RESET}"
  echo "───────────────────────────────────────────"
  echo -e "${CYAN}🌐 Domínio:${RESET} $dominio"
  echo -e "${CYAN}👤 Registrante:${RESET} ${owner:-(protegido)}"
  echo -e "${CYAN}📧 E-mail:${RESET} ${email:-(oculto)}"
  echo -e "${CYAN}🏢 Registrar:${RESET} $registrar"
  echo -e "${CYAN}📅 Criado em:${RESET} ${criacao:-—}"
  echo -e "${CYAN}♻️ Atualizado em:${RESET} ${atualizacao:-—}"
  echo -e "${CYAN}⏳ Expira em:${RESET} ${expiracao:-—}"
  echo -e "${CYAN}📡 Nameservers:${RESET}"
  echo "$data" | jq -r '.nameservers[]?.ldhName' | sed "s/^/   - /"

  return 0
}

# Loop principal
while true; do
    clear
    banner
    read -p "Digite o domínio: " dominio
    if ! consulta_rdap "$dominio"; then
        echo -e "\n${RED}❌ Ocorreu um erro na consulta RDAP!${RESET}"
        read -p "Pressione Enter para consultar outro domínio..."
        continue
    fi
    echo -e "\n${GREEN}✅ Consulta concluída!${RESET}"
    read -p "Pressione Enter para consultar outro domínio..."
done