#!/bin/bash
#
# Backup Diário Otimizado Zabbix Local — PostgreSQL
#

# ========================================
# CONFIGURAÇÕES - AJUSTAR PARA CADA CLIENTE
# ========================================

PG_USER="zabbix"
PG_PASS="newfl2022@"
PG_DB="zabbix"
PG_HOST="localhost"
PG_PORT="5432"

EXTERNALSCRIPTS_PATH="/usr/lib/zabbix/externalscripts"
ALERTSCRIPTS_PATH="/usr/lib/zabbix/alertscripts"

ZABBIX_SERVER_CONF="/etc/zabbix/zabbix_server.conf"
EXTRA_CONFIG_FILES=""

BACKUP_DIR="/opt/backup/zabbix"
RETENTION_COUNT_LOCAL=2
TRENDS_RETENTION_DAYS=15
LOG_FILE="/var/log/backup_zabbix.log"

SFTP_ENABLED=true
SFTP_HOST="172.21.2.50"
SFTP_PORT="4721"
SFTP_USER="bkpzbx"
SFTP_PASS="M003|CE1BVq_h4f:"
SFTP_DIR="/opt/bkp_zabbix/"
SFTP_RETENTION_DAYS=5

STATUS_FILE="/opt/backup/zabbix/backup_status.json"

# ========================================
# NÃO ALTERAR DAQUI PRA BAIXO
# ========================================

export PGPASSWORD="${PG_PASS}"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_CONFIG="${BACKUP_DIR}/backup_config_${DATE}.sql"
BACKUP_TRENDS="${BACKUP_DIR}/backup_trends_${DATE}.sql"
BACKUP_SCRIPTS="${BACKUP_DIR}/backup_scripts_${DATE}.tar.gz"
BACKUP_CONFIGS_TAR="${BACKUP_DIR}/backup_configs_${DATE}.tar.gz"

mkdir -p "${BACKUP_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

write_status() {
    local status="$1"
    local message="$2"
    local ts_unix
    local ts_human
    ts_unix=$(date +%s)
    ts_human=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "${STATUS_FILE}" << EOF
{
  "status": "${status}",
  "timestamp": ${ts_unix},
  "timestamp_human": "${ts_human}",
  "message": "${message}"
}
EOF
    chmod 644 "${STATUS_FILE}"
}

die() {
    local message="$1"
    log "ERRO: ${message}"
    write_status "ERRO" "${message}"
    exit 1
}

log "=== Iniciando backup otimizado do Zabbix (PostgreSQL) ==="

CUTOFF_TIMESTAMP=$(date -d "${TRENDS_RETENTION_DAYS} days ago" +%s)
log "Backup de trends desde: $(date -d @${CUTOFF_TIMESTAMP} '+%Y-%m-%d %H:%M:%S')"

# Testa conexão
psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" -c "SELECT 1;" > /dev/null 2>&1 \
    || die "Falha ao conectar no PostgreSQL — verifique usuário/senha/host"

# Backup de configurações (sem history, trends, auditlog)
log "Fazendo backup das configurações..."
pg_dump \
    -h "${PG_HOST}" \
    -p "${PG_PORT}" \
    -U "${PG_USER}" \
    -d "${PG_DB}" \
    --no-password \
    -T history \
    -T history_uint \
    -T history_str \
    -T history_text \
    -T history_log \
    -T trends \
    -T trends_uint \
    -T auditlog \
    -f "${BACKUP_CONFIG}" 2>> "${LOG_FILE}"

[ $? -eq 0 ] || die "Falha no pg_dump — backup de configurações"
log "Backup de configurações concluído"

# Backup de trends (últimos N dias via COPY)
log "Fazendo backup das trends (últimos ${TRENDS_RETENTION_DAYS} dias)..."

psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" -c \
    "SELECT 'trends' as tabela, COUNT(*) FROM trends WHERE clock >= ${CUTOFF_TIMESTAMP}
     UNION ALL
     SELECT 'trends_uint', COUNT(*) FROM trends_uint WHERE clock >= ${CUTOFF_TIMESTAMP};" \
    | tee -a "${LOG_FILE}"

{
    echo "COPY trends TO STDOUT WHERE clock >= ${CUTOFF_TIMESTAMP};" | \
        psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" \
        -c "\COPY (SELECT * FROM trends WHERE clock >= ${CUTOFF_TIMESTAMP}) TO STDOUT"

    echo "COPY trends_uint TO STDOUT WHERE clock >= ${CUTOFF_TIMESTAMP};" | \
        psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" \
        -c "\COPY (SELECT * FROM trends_uint WHERE clock >= ${CUTOFF_TIMESTAMP}) TO STDOUT"
} > "${BACKUP_TRENDS}" 2>> "${LOG_FILE}"

[ $? -eq 0 ] || die "Falha no psql COPY — backup de trends"
log "Backup de trends concluído"

# Backup dos scripts externos
log "Fazendo backup dos scripts externos..."
SCRIPTS_TO_BACKUP=""

[ -d "${EXTERNALSCRIPTS_PATH}" ] \
    && { log "  ✓ ExternalScripts: ${EXTERNALSCRIPTS_PATH}"; SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${EXTERNALSCRIPTS_PATH}"; } \
    || log "  ⚠ ExternalScripts não encontrado: ${EXTERNALSCRIPTS_PATH}"

[ -d "${ALERTSCRIPTS_PATH}" ] \
    && { log "  ✓ AlertScripts: ${ALERTSCRIPTS_PATH}"; SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${ALERTSCRIPTS_PATH}"; } \
    || log "  ⚠ AlertScripts não encontrado: ${ALERTSCRIPTS_PATH}"

if [ -n "${SCRIPTS_TO_BACKUP}" ]; then
    tar -czf "${BACKUP_SCRIPTS}" ${SCRIPTS_TO_BACKUP} 2>> "${LOG_FILE}" \
        && log "  ✓ Scripts: $(du -h ${BACKUP_SCRIPTS} | cut -f1)" \
        || log "  ✗ ERRO ao compactar scripts"
else
    log "  ⚠ Nenhum diretório de scripts encontrado"
    rm -f "${BACKUP_SCRIPTS}"
fi

# Backup dos arquivos de configuração
log "Fazendo backup dos arquivos de configuração..."
CONFIGS_TO_BACKUP=""

[ -n "${ZABBIX_SERVER_CONF}" ] && [ -f "${ZABBIX_SERVER_CONF}" ] \
    && { log "  ✓ zabbix_server.conf"; CONFIGS_TO_BACKUP="${CONFIGS_TO_BACKUP} ${ZABBIX_SERVER_CONF}"; } \
    || log "  ⚠ zabbix_server.conf não encontrado: ${ZABBIX_SERVER_CONF}"

for EXTRA_FILE in ${EXTRA_CONFIG_FILES}; do
    [ -f "${EXTRA_FILE}" ] \
        && { log "  ✓ Extra: ${EXTRA_FILE}"; CONFIGS_TO_BACKUP="${CONFIGS_TO_BACKUP} ${EXTRA_FILE}"; } \
        || log "  ⚠ Arquivo extra não encontrado: ${EXTRA_FILE}"
done

if [ -n "${CONFIGS_TO_BACKUP}" ]; then
    tar -czf "${BACKUP_CONFIGS_TAR}" ${CONFIGS_TO_BACKUP} 2>> "${LOG_FILE}" \
        && log "  ✓ Configs: $(du -h ${BACKUP_CONFIGS_TAR} | cut -f1)" \
        || { log "  ✗ ERRO ao compactar configs"; rm -f "${BACKUP_CONFIGS_TAR}"; }
else
    log "  ⚠ Nenhum arquivo de configuração para backup"
    rm -f "${BACKUP_CONFIGS_TAR}"
fi

# Compactar SQLs
log "Compactando arquivos SQL..."
gzip "${BACKUP_CONFIG}" && gzip "${BACKUP_TRENDS}" \
    || die "Falha ao compactar arquivos SQL"

# Montar tar final
log "Combinando em arquivo final..."
BACKUP_FINAL="${BACKUP_DIR}/backup_${DATE}.tar.gz"

EXTRA_ARGS=""
[ -f "${BACKUP_SCRIPTS}" ]     && EXTRA_ARGS="${EXTRA_ARGS} -C ${BACKUP_DIR} backup_scripts_${DATE}.tar.gz"
[ -f "${BACKUP_CONFIGS_TAR}" ] && EXTRA_ARGS="${EXTRA_ARGS} -C ${BACKUP_DIR} backup_configs_${DATE}.tar.gz"

tar -czf "${BACKUP_FINAL}" \
    -C "${BACKUP_DIR}" backup_config_${DATE}.sql.gz \
    -C "${BACKUP_DIR}" backup_trends_${DATE}.sql.gz \
    ${EXTRA_ARGS} 2>> "${LOG_FILE}" \
    || die "Falha ao montar tar final"

rm -f "${BACKUP_CONFIG}.gz" "${BACKUP_TRENDS}.gz" "${BACKUP_SCRIPTS}" "${BACKUP_CONFIGS_TAR}"

SIZE=$(du -h "${BACKUP_FINAL}" | cut -f1)
log "Backup final: ${BACKUP_FINAL} (${SIZE})"

# Retenção local
log "Aplicando retenção local (${RETENTION_COUNT_LOCAL} backups)..."
BACKUP_COUNT=$(ls -t "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null | wc -l)
if [ "${BACKUP_COUNT}" -gt "${RETENTION_COUNT_LOCAL}" ]; then
    ls -t "${BACKUP_DIR}"/backup_*.tar.gz | tail -n +$((RETENTION_COUNT_LOCAL + 1)) | xargs rm -f
    log "✓ Backups antigos removidos. Mantidos: ${RETENTION_COUNT_LOCAL}"
else
    log "Total: ${BACKUP_COUNT} backups. Nenhum removido."
fi

log "=== Backup local concluído ==="

# SFTP
if [ "${SFTP_ENABLED}" = true ]; then
    log "=== Iniciando envio SFTP ==="

    command -v sshpass > /dev/null 2>&1 || die "sshpass não instalado"

    SFTP_BATCH="/tmp/sftp_upload_$$.txt"
    cat > "${SFTP_BATCH}" << EOFBATCH
cd ${SFTP_DIR}
put ${BACKUP_FINAL}
bye
EOFBATCH

    log "Enviando para ${SFTP_HOST}:${SFTP_DIR}..."
    sshpass -p "${SFTP_PASS}" sftp \
        -P "${SFTP_PORT}" \
        -o StrictHostKeyChecking=no \
        -oBatchMode=no \
        -b "${SFTP_BATCH}" \
        "${SFTP_USER}@${SFTP_HOST}" >> "${LOG_FILE}" 2>&1 \
        || { rm -f "${SFTP_BATCH}"; die "Falha no upload SFTP — ${SFTP_HOST}"; }

    log "✓ Backup enviado para SFTP"

    log "Limpando backups remotos com mais de ${SFTP_RETENTION_DAYS} dias..."
    sshpass -p "${SFTP_PASS}" ssh \
        -p "${SFTP_PORT}" \
        -o StrictHostKeyChecking=no \
        "${SFTP_USER}@${SFTP_HOST}" \
        "find ${SFTP_DIR} -name 'backup_*.tar.gz' -mtime +${SFTP_RETENTION_DAYS} -delete && echo 'Limpeza remota OK'" \
        >> "${LOG_FILE}" 2>&1 \
        && log "✓ Limpeza remota concluída" \
        || log "⚠ Não foi possível limpar backups remotos"

    rm -f "${SFTP_BATCH}"
    log "=== Envio SFTP concluído ==="
fi

write_status "OK" "Backup concluído com sucesso"
log "=== Processo completo finalizado ==="

unset PGPASSWORD
exit 0