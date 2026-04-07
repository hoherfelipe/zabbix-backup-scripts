#!/bin/bash
#
# Backup Diário Otimizado Zabbix Local (sem history, trends 15 dias + scripts)
#

# ========================================
# CONFIGURAÇÕES - AJUSTAR PARA CADA CLIENTE
# ========================================

# Configurações do Container Docker
DOCKER_CONTAINER="NOME_DO_CONTAINER_MYSQL"                             # Container MySQL
ZABBIX_SERVER_CONTAINER="NOME_DO_CONTAINER_SERVER"                     # Container Zabbix Server
MYSQL_USER="USER"                                                  # Usuário do banco
MYSQL_PASS="SENHA"                                                 # Senha do banco
MYSQL_DB="NAME"                                                    # Nome do banco

# Configurações de Scripts Externos
EXTERNALSCRIPTS_PATH="/docker/zabbix-data/externalscripts"  # Caminho para externalscripts
ALERTSCRIPTS_PATH="/docker/zabbix-data/alertscripts"        # Caminho para alertscripts

# Arquivos de configuração extras para backup (separados por espaço)
# Deixe vazio ("") para desabilitar
EXTRA_CONFIG_FILES=""

# Configurações de Backup Local
BACKUP_DIR="/opt/backup/zabbix"          # Diretório local para backups
RETENTION_COUNT_LOCAL=2                  # Manter apenas os 2 últimos backups locais
TRENDS_RETENTION_DAYS=7                  # Backup apenas trends dos últimos X dias
LOG_FILE="/var/log/backup_zabbix_docker.log"

# Configurações SFTP/FTP (opcional - deixe SFTP_ENABLED=false para desabilitar)
SFTP_ENABLED=true                                           # true para ativar, false para desativar
SFTP_HOST="FTP_IP"
SFTP_PORT="FTP_PORT"
SFTP_USER="FTP_USER"
SFTP_PASS="FTP_PASSWORD"
SFTP_DIR="/opt/bkp_zabbix/"
SFTP_RETENTION_DAYS=5                                       # Retenção no servidor remoto

# Arquivo de status para monitoramento Zabbix
STATUS_FILE="/opt/backup/zabbix/backup_status.json"

# ========================================
# NÃO ALTERAR DAQUI PRA BAIXO
# ========================================

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_CONFIG="${BACKUP_DIR}/backup_config_${DATE}.sql"
BACKUP_TRENDS="${BACKUP_DIR}/backup_trends_${DATE}.sql"
BACKUP_SCRIPTS="${BACKUP_DIR}/backup_scripts_${DATE}.tar.gz"
BACKUP_CONFIGS_TAR="${BACKUP_DIR}/backup_configs_${DATE}.tar.gz"
ZABBIX_CONF_EXTRACTED="${BACKUP_DIR}/zabbix_server_${DATE}.conf"

mkdir -p ${BACKUP_DIR}

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Função para gravar status JSON (sobrescreve sempre)
write_status() {
    local status="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "${STATUS_FILE}" << EOF
{
  "status": "${status}",
  "timestamp": "${timestamp}",
  "message": "${message}"
}
EOF

    chmod 644 "${STATUS_FILE}"
}

# Função para encerrar com erro
die() {
    local message="$1"
    log "ERRO: ${message}"
    write_status "ERRO" "${message}"
    exit 1
}

log "=== Iniciando backup otimizado do Zabbix Local ==="

CUTOFF_TIMESTAMP=$(date -d "15 days ago" +%s)
log "Fazendo backup de trends desde: $(date -d @${CUTOFF_TIMESTAMP} '+%Y-%m-%d %H:%M:%S')"

# Backup de configurações MySQL
log "Fazendo backup das configurações..."
docker exec ${DOCKER_CONTAINER} mysqldump -u"${MYSQL_USER}" -p"${MYSQL_PASS}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --no-tablespaces \
    --ignore-table=${MYSQL_DB}.history \
    --ignore-table=${MYSQL_DB}.history_uint \
    --ignore-table=${MYSQL_DB}.history_str \
    --ignore-table=${MYSQL_DB}.history_text \
    --ignore-table=${MYSQL_DB}.history_log \
    --ignore-table=${MYSQL_DB}.trends \
    --ignore-table=${MYSQL_DB}.trends_uint \
    --ignore-table=${MYSQL_DB}.auditlog \
    ${MYSQL_DB} > ${BACKUP_CONFIG} 2>> ${LOG_FILE}

if [ $? -ne 0 ]; then
    die "Falha no mysqldump - backup de configurações"
fi

log "Backup de configurações concluído"

# Backup das trends
log "Fazendo backup das trends (últimos ${TRENDS_RETENTION_DAYS} dias)..."
docker exec ${DOCKER_CONTAINER} mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" "${MYSQL_DB}" -N -e \
    "SELECT 'trends' as table_name, COUNT(*) as records FROM trends WHERE clock >= ${CUTOFF_TIMESTAMP}
     UNION ALL
     SELECT 'trends_uint', COUNT(*) FROM trends_uint WHERE clock >= ${CUTOFF_TIMESTAMP};" \
    | tee -a ${LOG_FILE}

docker exec ${DOCKER_CONTAINER} mysqldump -u"${MYSQL_USER}" -p"${MYSQL_PASS}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --no-tablespaces \
    ${MYSQL_DB} trends trends_uint \
    --where="clock >= ${CUTOFF_TIMESTAMP}" > ${BACKUP_TRENDS} 2>> ${LOG_FILE}

if [ $? -ne 0 ]; then
    die "Falha no mysqldump - backup de trends"
fi

log "Backup de trends concluído"

# Backup dos scripts externos
log "Fazendo backup dos scripts externos..."
SCRIPTS_TO_BACKUP=""

if [ -d "${EXTERNALSCRIPTS_PATH}" ]; then
    log "  ✓ ExternalScripts encontrado: ${EXTERNALSCRIPTS_PATH}"
    SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${EXTERNALSCRIPTS_PATH}"
else
    log "  ⚠ ExternalScripts não encontrado em: ${EXTERNALSCRIPTS_PATH}"
fi

if [ -d "${ALERTSCRIPTS_PATH}" ]; then
    log "  ✓ AlertScripts encontrado: ${ALERTSCRIPTS_PATH}"
    SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${ALERTSCRIPTS_PATH}"
else
    log "  ⚠ AlertScripts não encontrado em: ${ALERTSCRIPTS_PATH}"
fi

if [ -n "${SCRIPTS_TO_BACKUP}" ]; then
    tar -czf ${BACKUP_SCRIPTS} ${SCRIPTS_TO_BACKUP} 2>> ${LOG_FILE}

    if [ $? -eq 0 ]; then
        SCRIPTS_SIZE=$(du -h ${BACKUP_SCRIPTS} | cut -f1)
        log "  ✓ Backup de scripts concluído: ${SCRIPTS_SIZE}"
    else
        log "  ✗ ERRO ao fazer backup dos scripts!"
    fi
else
    log "  ⚠ Nenhum diretório de scripts encontrado para backup"
    rm -f ${BACKUP_SCRIPTS}
fi

# Backup dos arquivos de configuração
log "Fazendo backup dos arquivos de configuração..."
CONFIGS_TO_BACKUP=""

# Extrair zabbix_server.conf do container Zabbix Server
docker cp ${ZABBIX_SERVER_CONTAINER}:/etc/zabbix/zabbix_server.conf ${ZABBIX_CONF_EXTRACTED} 2>> ${LOG_FILE}

if [ $? -eq 0 ]; then
    log "  ✓ zabbix_server.conf extraído do container ${ZABBIX_SERVER_CONTAINER}"
    CONFIGS_TO_BACKUP="${CONFIGS_TO_BACKUP} ${ZABBIX_CONF_EXTRACTED}"
else
    log "  ⚠ Não foi possível extrair zabbix_server.conf do container ${ZABBIX_SERVER_CONTAINER}"
fi

# Arquivos extras do host
for EXTRA_FILE in ${EXTRA_CONFIG_FILES}; do
    if [ -f "${EXTRA_FILE}" ]; then
        log "  ✓ Arquivo extra encontrado: ${EXTRA_FILE}"
        CONFIGS_TO_BACKUP="${CONFIGS_TO_BACKUP} ${EXTRA_FILE}"
    else
        log "  ⚠ Arquivo extra não encontrado: ${EXTRA_FILE}"
    fi
done

if [ -n "${CONFIGS_TO_BACKUP}" ]; then
    tar -czf ${BACKUP_CONFIGS_TAR} ${CONFIGS_TO_BACKUP} 2>> ${LOG_FILE}

    if [ $? -eq 0 ]; then
        CONFIGS_SIZE=$(du -h ${BACKUP_CONFIGS_TAR} | cut -f1)
        log "  ✓ Backup de arquivos de configuração concluído: ${CONFIGS_SIZE}"
    else
        log "  ✗ ERRO ao fazer backup dos arquivos de configuração!"
        rm -f ${BACKUP_CONFIGS_TAR}
    fi
else
    log "  ⚠ Nenhum arquivo de configuração encontrado para backup"
    rm -f ${BACKUP_CONFIGS_TAR}
fi

# Limpar conf extraído temporariamente do container
rm -f ${ZABBIX_CONF_EXTRACTED} 2>/dev/null

# Compactar
log "Compactando backups SQL..."
gzip ${BACKUP_CONFIG}
gzip ${BACKUP_TRENDS}

if [ $? -ne 0 ]; then
    die "Falha ao compactar arquivos SQL"
fi

# Combinar
log "Combinando arquivos..."
BACKUP_FINAL="${BACKUP_DIR}/backup_${DATE}.tar.gz"

tar -czf ${BACKUP_FINAL} \
    -C ${BACKUP_DIR} backup_config_${DATE}.sql.gz \
    -C ${BACKUP_DIR} backup_trends_${DATE}.sql.gz \
    $([ -f ${BACKUP_SCRIPTS} ] && echo "-C ${BACKUP_DIR} backup_scripts_${DATE}.tar.gz") \
    $([ -f ${BACKUP_CONFIGS_TAR} ] && echo "-C ${BACKUP_DIR} backup_configs_${DATE}.tar.gz") \
    2>> ${LOG_FILE}

if [ $? -ne 0 ]; then
    die "Falha ao combinar arquivos no tar final"
fi

# Limpar arquivos temporários
rm -f ${BACKUP_CONFIG}.gz ${BACKUP_TRENDS}.gz ${BACKUP_SCRIPTS} ${BACKUP_CONFIGS_TAR}

SIZE=$(du -h ${BACKUP_FINAL} | cut -f1)
log "Tamanho do backup final: ${SIZE}"
log "Arquivo: ${BACKUP_FINAL}"

# Remover backups antigos
log "Mantendo apenas os ${RETENTION_COUNT_LOCAL} backups mais recentes localmente..."
BACKUP_COUNT=$(ls -t ${BACKUP_DIR}/backup_*.tar.gz 2>/dev/null | wc -l)

if [ ${BACKUP_COUNT} -gt ${RETENTION_COUNT_LOCAL} ]; then
    log "Encontrados ${BACKUP_COUNT} backups, removendo os mais antigos..."
    ls -t ${BACKUP_DIR}/backup_*.tar.gz | tail -n +$((RETENTION_COUNT_LOCAL + 1)) | xargs rm -f
    log "✓ Backups antigos removidos. Mantidos os ${RETENTION_COUNT_LOCAL} mais recentes."
else
    log "Total de ${BACKUP_COUNT} backups. Nenhum backup removido."
fi

log "=== Backup local concluído com sucesso ==="

# Upload SFTP
if [ "$SFTP_ENABLED" = true ]; then
    log "=== Iniciando envio para servidor SFTP ==="

    if ! command -v sshpass &> /dev/null; then
        die "sshpass não está instalado - backup não enviado para SFTP"
    fi

    SFTP_BATCH="/tmp/sftp_upload_$$.txt"
    cat > ${SFTP_BATCH} << EOFBATCH
cd ${SFTP_DIR}
put ${BACKUP_FINAL}
ls -lh backup_${DATE}.tar.gz
bye
EOFBATCH

    log "Enviando ${BACKUP_FINAL} para ${SFTP_HOST}:${SFTP_DIR}..."
    sshpass -p "${SFTP_PASS}" sftp -P ${SFTP_PORT} -o StrictHostKeyChecking=no -oBatchMode=no -b ${SFTP_BATCH} ${SFTP_USER}@${SFTP_HOST} >> ${LOG_FILE} 2>&1

    if [ $? -ne 0 ]; then
        rm -f ${SFTP_BATCH}
        die "Falha ao enviar backup para SFTP - ${SFTP_HOST}"
    fi

    log "✓ Backup enviado com sucesso para SFTP: ${SFTP_HOST}"

    # Limpar backups antigos no SFTP
    log "Limpando backups remotos com mais de ${SFTP_RETENTION_DAYS} dias..."
    sshpass -p "${SFTP_PASS}" ssh -p ${SFTP_PORT} -o StrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST} << EOFSSH >> ${LOG_FILE} 2>&1
cd ${SFTP_DIR}
find . -name "backup_*.tar.gz" -mtime +${SFTP_RETENTION_DAYS} -delete
echo "Backups antigos removidos"
EOFSSH

    if [ $? -eq 0 ]; then
        log "✓ Limpeza de backups remotos concluída"
    else
        log "⚠ Não foi possível limpar backups remotos antigos"
    fi

    rm -f ${SFTP_BATCH}
    log "=== Envio para SFTP concluído ==="
fi

# Gravar status de sucesso
write_status "OK" "Backup concluído com sucesso"

log "=== Processo completo finalizado ==="

exit 0