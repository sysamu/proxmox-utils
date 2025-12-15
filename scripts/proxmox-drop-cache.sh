#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
MIN_CACHE_KB=262144   # 256 MB
# ====================

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
BOLD="\e[1m"
RESET="\e[0m"

cache_sum() {
  awk '/^Cached:|^Buffers:|^SReclaimable:/ {sum+=$2} END {print sum}' /proc/meminfo
}

to_mb() {
  awk "BEGIN {printf \"%.2f\", $1/1024}"
}

clear
echo -e "${BOLD}${BLUE}🧠 Proxmox cache cleanup report${RESET}"
echo "----------------------------------------"

before=$(cache_sum)

echo -e "Cache liberable detectada: ${BOLD}$(to_mb "$before") MB${RESET}"

if (( before < MIN_CACHE_KB )); then
  echo
  echo -e "${YELLOW}⚠ Cache < 256 MB. Probablemente NO merece la pena.${RESET}"
  proceed_default="n"
else
  echo
  echo -e "${GREEN}✔ Cache suficiente para limpiar.${RESET}"
  proceed_default="y"
fi

echo
read -rp "¿Proceder con drop_caches? [y/N]: " answer
answer=${answer:-$proceed_default}

if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo
  echo -e "${BLUE}ℹ Operación cancelada. No se ha tocado nada.${RESET}"
  exit 0
fi

echo
echo -e "${YELLOW}→ Syncing disks...${RESET}"
sync

echo -e "${YELLOW}→ Dropping pagecache, dentries and inodes...${RESET}"
echo 3 > /proc/sys/vm/drop_caches

sleep 1

after=$(cache_sum)
freed=$((before-after))

echo
echo -e "${BOLD}Resultados:${RESET}"
echo -e "  Cache antes   : $(to_mb "$before") MB"
echo -e "  Cache después : $(to_mb "$after") MB"

if (( freed > 0 )); then
  echo -e "  ${GREEN}Liberado       : $(to_mb "$freed") MB${RESET}"
else
  echo -e "  ${RED}Liberado       : 0 MB (sin impacto real)${RESET}"
fi

echo
echo -e "${BLUE}Estado de memoria actual:${RESET}"
free -h
