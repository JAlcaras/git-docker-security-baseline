#!/usr/bin/env bash
# =============================================================================
# validar-modelos.sh | Git + Docker Security Baseline v4 (revisao)
# Politica equilibrada: bloquear riscos criticos, avisar sobre ambiguidades.
# Modo rules: testar regras Git e requisitos explicitos da baseline Docker.
# Modo build: os mesmos testes + inspecao do contexto REAL ja filtrado.
# Nao valida imagem final, camadas anteriores nem todas as classes de segredos.
# =============================================================================
set -euo pipefail

usage() {
  cat <<'HELP'
Uso:
  bash validar-modelos.sh --check-rules [--rules-dir DIR]
  bash validar-modelos.sh --context DIR [--rules-dir DIR] [--require-path ARQUIVO]...

  --check-rules        Testa as regras Git e a politica minima do .dockerignore.
  --context DIR        Tambem inspeciona os arquivos reais disponiveis em DIR.
                       Utilize o contexto filtrado montado durante docker build.
  --rules-dir DIR      Diretorio contendo .gitignore e .dockerignore.
                       Padrao: diretorio onde este script esta salvo.
  --require-path REL   Exige que um caminho relativo exista no contexto;
                       pode ser repetido para os arquivos essenciais do app.
  -h, --help           Esta ajuda.

Exit 0 = verificacoes executadas aprovadas (avisos podem existir)
Exit 1 = politica reprovada ou arquivo suspeito detectado
Exit 2 = erro de uso, configuracao ou dependencia

IMPORTANTE: --context verifica o contexto JA filtrado pelo Docker.
            Nao prova ausencia de segredos na imagem final.
HELP
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RULES_DIR="$SCRIPT_DIR"
MODE='rules'
CONTEXT=''
REQUIRED_PATHS=()

while (( $# > 0 )); do
  case "$1" in
    --check-rules) MODE='rules'; shift ;;
    --context)
      (( $# >= 2 )) || { echo 'ERRO: --context exige diretorio.' >&2; exit 2; }
      CONTEXT="$2"; MODE='build'; shift 2 ;;
    --rules-dir)
      (( $# >= 2 )) || { echo 'ERRO: --rules-dir exige diretorio.' >&2; exit 2; }
      RULES_DIR="$2"; shift 2 ;;
    --require-path)
      (( $# >= 2 )) || { echo 'ERRO: --require-path exige caminho.' >&2; exit 2; }
      REQUIRED_PATHS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERRO: argumento nao reconhecido: %q\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$RULES_DIR" ]] || { echo 'ERRO: --rules-dir nao existe.' >&2; exit 2; }
RULES_DIR="$(cd -- "$RULES_DIR" && pwd -P)"
[[ -s "$RULES_DIR/.gitignore" && -s "$RULES_DIR/.dockerignore" ]] || {
  echo 'ERRO: .gitignore e .dockerignore devem existir e nao estar vazios.' >&2
  exit 2
}
if [[ "$MODE" == build ]]; then
  [[ -n "$CONTEXT" && -d "$CONTEXT" ]] || {
    echo 'ERRO: --context exige diretorio existente.' >&2; exit 2;
  }
  CONTEXT="$(cd -- "$CONTEXT" && pwd -P)"
else
  (( ${#REQUIRED_PATHS[@]} == 0 )) || {
    echo 'ERRO: --require-path exige --context.' >&2; exit 2;
  }
fi

for tool in git grep find mktemp cp rm wc sed; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'ERRO: dependencia ausente: %s\n' "$tool" >&2; exit 2;
  }
done

ERRORS=0
WARNINGS=0
GIT_OK=0
GIT_TOTAL=0

block() {
  printf '[BLOQUEIO] %s\n' "$1" >&2
  ERRORS=$((ERRORS + 1))
}
warn() {
  printf '[AVISO] %s\n' "$1" >&2
  WARNINGS=$((WARNINGS + 1))
}

# 1. Git: verifica padroes reais usando motor oficial do Git, sem depender
# do .git do usuario nem de arquivos globais do ambiente de execucao.
TMP="$(mktemp -d)" || { echo 'ERRO: mktemp falhou.' >&2; exit 2; }
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$RULES_DIR/.gitignore" "$TMP/.gitignore"
# Aceitar arquivos .dockerignore com finais de linha LF ou CRLF.
if ! sed 's/\r$//' "$RULES_DIR/.dockerignore" > "$TMP/dockerignore.normalized"; then
  echo 'ERRO: falha lendo .dockerignore.' >&2; exit 2
fi
(
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git -C "$TMP" init -q
) || { echo 'ERRO: git init falhou no teste temporario.' >&2; exit 2; }

GIT_MUST_DROP=(
  '.env' 'nested/.env.production' 'src/app.env' 'src/app.env.local'
  'nested/private.key' 'nested/id_ed25519' 'nested/.aws/credentials'
  'infra/terraform.tfstate' 'infra/app.tfvars'
  'nested/.cursor/mcp.json' 'nested/.mcp.json'
  'nested/.docker/config.json' 'nested/.npmrc'
  'nested/node_modules/package.js' 'nested/backup.sql.gz'
  '.vscode/settings.json' 'CLAUDE.local.md'
)
GIT_MUST_KEEP=(
  '.env.example' 'nested/.env.example' 'src/app.env.example'
  '.env.sample' 'src/app.env.template' 'AGENTS.md' 'CLAUDE.md'
  'src/main.js' 'tests/unit.test.js' 'docs/README.md'
  'database/migrations/001.sql' 'app/bin/www' 'app/vendor/tool.php'
  'app/dist/index.js' 'package-lock.json' 'composer.lock'
  'infra/.terraform.lock.hcl' '.vscode/extensions.json' 'LICENSE'
)

check_git() {
  local expected="$1" path="$2" found=0 rc=0
  GIT_TOTAL=$((GIT_TOTAL + 1))
  if (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    git -c core.excludesFile=/dev/null -C "$TMP" \
      check-ignore --no-index -q -- "$path"
  ); then
    found=1
  else
    rc=$?
    case "$rc" in
      1) found=0 ;;
      *) block "Git: erro tecnico (${rc}) verificando caminho $(printf '%q' "$path")"; return ;;
    esac
  fi
  if [[ "$expected" != "$found" ]]; then
    block "Git: $(printf '%q' "$path") deveria ser ignorado=$expected, observado=$found"
  else
    GIT_OK=$((GIT_OK + 1))
  fi
}
for path in "${GIT_MUST_DROP[@]}"; do check_git 1 "$path"; done
for path in "${GIT_MUST_KEEP[@]}"; do check_git 0 "$path"; done
printf 'Git: %d/%d cenarios de regras aprovados.\n' "$GIT_OK" "$GIT_TOTAL"

# 2. Docker: contrato MINIMO da baseline (verificacao estrutural, nao motor
# Docker). Exige padroes canonicos; regras equivalentes editadas precisam
# de revisao do contrato. O contexto REAL e inspecionado no passo seguinte.
DOCKER_REQUIRED=(
  '**/.env' '**/.env.*' '**/*.env' '**/*.env.*'
  '**/.git' '**/.aws' '**/.ssh' '**/.mcp.json'
  '**/*.key' '**/*.p12' '**/credentials.json'
  '**/*.tfstate' '**/*.tfstate.*'
)
DOCKER_OK=0
for pattern in "${DOCKER_REQUIRED[@]}"; do
  if grep -Fxq -- "$pattern" "$TMP/dockerignore.normalized"; then
    DOCKER_OK=$((DOCKER_OK + 1))
  else
    block "Docker: protecao obrigatoria ausente: $pattern"
  fi
done
printf 'Docker: %d/%d padroes obrigatorios presentes (checagem estatica).\n' \
  "$DOCKER_OK" "${#DOCKER_REQUIRED[@]}"

# Excecoes podem neutralizar padroes anteriores. Bloquear reabilitacoes
# explicitamente perigosas e avisar sobre excecoes nao padronizadas.
SAFE_EXCEPTIONS=(
  '!**/.env.example' '!**/.env.sample' '!**/.env.template'
  '!**/*.env.example' '!**/*.env.sample' '!**/*.env.template'
  '!**/storage/**/.gitignore' '!/.gitignore' '!/.dockerignore'
)
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ "$line" == '!'* ]] || continue
  safe=0
  for approved in "${SAFE_EXCEPTIONS[@]}"; do
    if [[ "$line" == "$approved" ]]; then safe=1; break; fi
  done
  (( safe )) && continue
  unignore="${line#!}"
  case "$unignore" in
    '*'|'**'|'**/*'|*'.env'*|*'.aws'*|*'.ssh'*|*'.git/'*|*'.git'|*'credentials'*|*'tfstate'*|*'.mcp.json'*)
      block "Docker: excecao potencialmente perigosa: $(printf '%q' "$line")" ;;
    *"*"*|*"?"*|*"["*)
      block "Docker: excecao adicional com wildcard nao revisada: $(printf '%q' "$line")" ;;
    *) warn "Docker: excecao individual; revisar justificativa e conteudo: $(printf '%q' "$line")" ;;
  esac
done < "$TMP/dockerignore.normalized"

if [[ "$MODE" == rules ]]; then
  if (( ERRORS > 0 )); then
    printf 'RESULTADO: REPROVADO (%d erros, %d avisos).\n' "$ERRORS" "$WARNINGS" >&2
    exit 1
  fi
  printf 'RESULTADO: REGRAS APROVADAS (%d avisos). Contexto real NAO inspecionado.\n' "$WARNINGS"
  exit 0
fi

# 3. Contexto REAL: somente o que o builder entregou apos .dockerignore.
# Nao copiar . ou secrets antes desta etapa no Dockerfile.
for required in "${REQUIRED_PATHS[@]}"; do
  case "$required" in
    ''|/*|..|../*|*/../*|*/..)
      printf 'ERRO de configuracao: --require-path invalido: %q\n' "$required" >&2; exit 2 ;;
  esac
  [[ -e "$CONTEXT/$required" ]] || block "Arquivo necessario removido/ausente do contexto: $(printf '%q' "$required")"
done

SCAN_FILES=0
classify_path() {
  local rel="$1" path="$2" name="${rel##*/}" full="/$rel"
  # Segmentos de acesso, metadados Git e configuracoes pessoais.
  case "$full" in
    */.git|*/.git/*|*/.aws|*/.aws/*|*/.ssh|*/.ssh/*|*/.azure/*|*/.gcp/*|*/.kube/*|*/.config/gcloud/*|*/.claude/*|*/.cursor/mcp.json|*/.docker/config.json|*/.secrets/*|*/secrets.local/*|*/local-secrets/*|*/.env/*|*/.env.*/*)
      block "Caminho sensivel presente no contexto: $(printf '%q' "$rel")"; return ;;
  esac
  case "$name" in
    .env.example|.env.sample|.env.template|*.env.example|*.env.sample|*.env.template)
      ;; # Exemplos podem entrar; conteudo ainda sera verificado.
    .env|.env.*|*.env|*.env.*)
      block "Arquivo de ambiente presente no contexto: $(printf '%q' "$rel")"; return ;;
  esac
  case "$name" in
    .git|.netrc|.s3cfg|.git-credentials|.mcp.json|*.tfstate|*.tfstate.*|*.tfvars|*.tfvars.json|*.tfplan|*.tfplan.*|credentials.json|*credentials*.json|secrets.json|*.secrets.json|auth.json|privkey*.pem|id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*|*.key|*.pfx|*.p12|*.jks|*.keystore|*.ppk|*.dump|*.sql.gz|*.sql.zip|*.wpress)
      block "Arquivo de alto risco presente no contexto: $(printf '%q' "$rel")"; return ;;
    *.pem|.npmrc|.pypirc|appsettings.Development.json|*.sqlite|*.sqlite3|*.db|dump*.sql|backup*.sql)
      warn "Arquivo ambiguo presente; revisar necessidade e conteudo: $(printf '%q' "$rel")" ;;
    AGENTS.md|CLAUDE.md|GEMINI.md|.cursorrules)
      warn "Instrucao de agente de IA presente no contexto: $(printf '%q' "$rel")" ;;
  esac
  # Procurar assinaturas de alta confianca em arquivos pequenos.
  # Exibir SOMENTE o caminho do arquivo, nunca o valor encontrado.
  if [[ -L "$path" ]]; then
    warn "Link simbolico: destino nao e inspecionado: $(printf '%q' "$rel")"
  fi
  if [[ -f "$path" && ! -L "$path" ]]; then
    local bytes grep_rc=0
    if ! bytes="$(wc -c < "$path")"; then
      printf 'ERRO tecnico lendo tamanho de %q\n' "$rel" >&2; exit 2
    fi
    if (( bytes <= 2097152 )); then
      # Em arquivos de configuracao de registry, uma diretiva de token/senha
      # identificada e bloqueada, mesmo sem reconhecer o valor da credencial.
      if [[ "$name" == '.npmrc' || "$name" == '.pypirc' ]]; then
        if LC_ALL=C grep -Eiq -- '(_authToken|_password|^[[:space:]]*(password|_auth)[[:space:]]*=)' "$path"; then
          block "Diretiva de credencial em configuracao local: $(printf '%q' "$rel")"
        fi
      fi
      if LC_ALL=C grep -Eaq -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|AKIA[A-Z0-9]{16}|ASIA[A-Z0-9]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}' "$path"; then
        block "Assinatura potencial de segredo encontrada em: $(printf '%q' "$rel")"
      else
        grep_rc=$?
        if (( grep_rc != 1 )); then
          printf 'ERRO tecnico lendo arquivo %q (grep=%s)\n' "$rel" "$grep_rc" >&2
          exit 2
        fi
      fi
    else
      warn "Conteudo nao inspecionado (>2 MiB): $(printf '%q' "$rel")"
    fi
  fi
}

# -print0 preserva nomes com espacos, tabs e quebras de linha.
if ! find "$CONTEXT" \( -type f -o -type l \) -print0 > "$TMP/context-paths"; then
  echo 'ERRO tecnico: impossivel enumerar o contexto.' >&2; exit 2
fi
while IFS= read -r -d '' file; do
  rel="${file#"$CONTEXT"/}"
  SCAN_FILES=$((SCAN_FILES + 1))
  classify_path "$rel" "$file"
done < "$TMP/context-paths"

printf 'Contexto efetivo: %d arquivos/links examinados; %d avisos; %d bloqueios.\n' \
  "$SCAN_FILES" "$WARNINGS" "$ERRORS"
if (( ERRORS > 0 )); then
  printf 'RESULTADO: REPROVADO. O Dockerfile deve interromper o build.\n' >&2
  exit 1
fi
printf 'RESULTADO: APROVADO no escopo definido (nao equivale a auditar a imagem final).\n'
exit 0
