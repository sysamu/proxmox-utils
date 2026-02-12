#!/bin/bash
# passgen.sh — Generador de contraseñas/passphrases seguras
# Uso: curl -sL <url>/passgen.sh | bash
# Uso: curl -sL <url>/passgen.sh | bash -s -- --passphrase
# Uso: curl -sL <url>/passgen.sh | bash -s -- --length 24
# Uso: curl -sL <url>/passgen.sh | bash -s -- --passphrase --words 6
# Uso: curl -sL <url>/passgen.sh | bash -s -- --tech
# Uso: curl -sL <url>/passgen.sh | bash -s -- --htpass --user admin

set -euo pipefail

# === Defaults ===
MODE="password"
LENGTH=""
WORDS=4
SEPARATOR="-"
HTPASS=""
HTPASS_USER=""

# === Parse args ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        --passphrase) MODE="passphrase"; shift ;;
        --tech)       MODE="tech"; shift ;;
        --length)     LENGTH="$2"; shift 2 ;;
        --words)      WORDS="$2"; shift 2 ;;
        --separator)  SEPARATOR="$2"; shift 2 ;;
        --htpass)     HTPASS=1; shift ;;
        --user)       HTPASS_USER="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
passgen.sh — Generador de contraseñas seguras

USO:
  bash passgen.sh [opciones]
  curl -sL <url>/passgen.sh | bash -s -- [opciones]

MODOS:
  (por defecto)    Genera una contraseña aleatoria
  --passphrase     Genera una frase de contraseña en español
  --tech           Genera token base64 (openssl rand -base64 32)

OPCIONES MODO PASSWORD:
  --length N       Longitud de la contraseña (mínimo 16, default: 16)

OPCIONES MODO PASSPHRASE:
  --words N        Número de palabras (mínimo 4, default: 4)
  --separator C    Separador entre palabras (default: -)

  Requiere: sudo apt install wspanish

OPCIONES MODO TECH:
  --length N       Bytes de entropía para openssl (default: 32 → 44 chars)

HTPASSWD (opcional, combinable con cualquier modo):
  --htpass         Genera también la línea htpasswd (Apache apr1)
  --user NAME      Usuario para la línea htpasswd (default: example)

HELP
            exit 0
            ;;
        *) echo "ERROR: Opción desconocida: $1" >&2; exit 1 ;;
    esac
done

# === Password mode ===
generate_password() {
    local len=${LENGTH:-16}

    if [[ $len -lt 16 ]]; then
        echo "ERROR: La longitud mínima es 16 caracteres." >&2
        exit 1
    fi

    # Caracteres seguros para curl|bash/powershell (sin $, \, `, ', ", &, |, ;, etc.)
    # El guión (-) va al final para que tr no lo interprete como rango
    local charset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#?!._-"

    local password=""
    while true; do
        # Generar candidata usando /dev/urandom
        password=$(LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$len" 2>/dev/null || true)

        # Verificar que cumple todos los requisitos
        [[ "$password" =~ [A-Z] ]] || continue
        [[ "$password" =~ [a-z] ]] || continue
        [[ "$password" =~ [0-9] ]] || continue
        [[ "$password" == *[#?!._-]* ]] || continue

        break
    done

    echo "$password"
}

# === Passphrase mode ===
generate_passphrase() {
    # Buscar diccionario en múltiples ubicaciones
    local dict=""
    for path in \
        /usr/share/dict/spanish \
        /usr/local/share/dict/spanish \
        "$HOME/.local/share/dict/spanish"; do
        if [[ -f "$path" ]]; then
            dict="$path"
            break
        fi
    done

    if [[ -z "$dict" ]]; then
        echo "ERROR: Diccionario español no encontrado." >&2
        echo "       Linux:  sudo apt install wspanish" >&2
        echo "       macOS:  brew install aspell && mkdir -p ~/.local/share/dict && aspell dump master es | sort -u > ~/.local/share/dict/spanish" >&2
        exit 1
    fi

    if [[ $WORDS -lt 4 ]]; then
        echo "ERROR: El mínimo de palabras es 4." >&2
        exit 1
    fi

    # Filtrar palabras: solo minúsculas, sin acentos/ñ/diéresis, longitud 4-8
    local wordlist
    wordlist=$(grep -E '^[a-z]{4,8}$' "$dict" | sort -u)

    local count
    count=$(echo "$wordlist" | wc -l)

    if [[ $count -lt 500 ]]; then
        echo "ERROR: Diccionario demasiado pequeño tras filtrar ($count palabras)." >&2
        exit 1
    fi

    local parts=()
    for ((i = 0; i < WORDS; i++)); do
        local idx digit
        idx=$(( $(od -An -tu4 -N4 /dev/urandom | tr -d ' ') % count + 1 ))
        digit=$(( $(od -An -tu4 -N4 /dev/urandom | tr -d ' ') % 10 ))
        parts+=("$(echo "$wordlist" | sed -n "${idx}p")${digit}")
    done

    local passphrase
    passphrase=$(IFS="$SEPARATOR"; echo "${parts[*]}")

    echo "$passphrase"
}

# === Tech mode (base64 token) ===
generate_tech() {
    local bytes=${LENGTH:-32}

    if ! command -v openssl &>/dev/null; then
        echo "ERROR: openssl no está instalado." >&2
        exit 1
    fi

    openssl rand -base64 "$bytes"
}

# === Main ===
result=$(
    case "$MODE" in
        password)    generate_password ;;
        passphrase)  generate_passphrase ;;
        tech)        generate_tech ;;
    esac
)

echo "Password: $result"

# === htpasswd output (opcional) ===
if [[ -n "$HTPASS" ]]; then
    local_user="${HTPASS_USER:-example}"

    if ! command -v openssl &>/dev/null; then
        echo "ERROR: openssl es necesario para --htpass" >&2
        exit 1
    fi

    hash=$(echo "$result" | openssl passwd -apr1 -stdin)
    echo "htpasswd: ${local_user}:${hash}"
fi
