#!/bin/bash
#
# Backup Diário Otimizado Zabbix Local (sem history, trends 15 dias + scripts)
#

# ========================================
# CONFIGURAÇÕES - AJUSTAR PARA CADA CLIENTE
# ========================================

# Configurações do MySQL/MariaDB
MYSQL_USER="USUARIO"                                        # Usuário do banco
MYSQL_PASS="SENHA"                                          # Senha do banco
MYSQL_DB="NOME_DO_BANCO"                                    # Nome do banco

# Configurações de Scripts Externos
EXTERNALSCRIPTS_PATH="/docker/zabbix-data/externalscripts"  # Caminho para externalscripts
ALERTSCRIPTS_PATH="/docker/zabbix-data/alertscripts"        # Caminho para alertscripts

# Configurações de Backup Local
BACKUP_DIR="/opt/backup/zabbix"                             # Diretório local para backups
RETENTION_COUNT_LOCAL=2                                     # Manter apenas os 2 últimos backups locais
TRENDS_RETENTION_DAYS=15                                    # Backup apenas trends dos últimos 15 dias
LOG_FILE="/var/log/backup_zabbix_docker.log"

# Configurações SFTP/FTP (opcional - deixe SFTP_ENABLED=false para desabilitar)
SFTP_ENABLED=true                                           # true para ativar, false para desativar
SFTP_HOST="IP_FTP"
SFTP_PORT="PORTA_FTP"
SFTP_USER="USUARIO_FTP"
SFTP_PASS="SENHA_FTP"
SFTP_DIR="/opt/bkp_zabbix"
SFTP_RETENTION_DAYS=5                                       # Retenção no servidor remoto

# ========================================
# NÃO ALTERAR DAQUI PRA BAIXO
# ========================================

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_CONFIG="${BACKUP_DIR}/backup_config_${DATE}.sql"
BACKUP_TRENDS="${BACKUP_DIR}/backup_trends_${DATE}.sql"
BACKUP_SCRIPTS="${BACKUP_DIR}/backup_scripts_${DATE}.tar.gz"

# Criar diretório se não existir
mkdir -p ${BACKUP_DIR}

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

log "=== Iniciando backup otimizado do Zabbix Local ==="

# Calcular timestamp de 15 dias atrás
CUTOFF_TIMESTAMP=$(date -d "15 days ago" +%s)
log "Fazendo backup de trends desde: $(date -d @${CUTOFF_TIMESTAMP} '+%Y-%m-%d %H:%M:%S')"

# Backup de configurações (SEM history e SEM trends)
log "Fazendo backup das configurações..."
mysqldump -u${MYSQL_USER} -p${MYSQL_PASS} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --ignore-table=${MYSQL_DB}.history \
    --ignore-table=${MYSQL_DB}.history_uint \
    --ignore-table=${MYSQL_DB}.history_str \
    --ignore-table=${MYSQL_DB}.history_text \
    --ignore-table=${MYSQL_DB}.history_log \
    --ignore-table=${MYSQL_DB}.trends \
    --ignore-table=${MYSQL_DB}.trends_uint \
    ${MYSQL_DB} > ${BACKUP_CONFIG} 2>> ${LOG_FILE}

if [ $? -ne 0 ]; then
    log "ERRO: Falha ao fazer backup das configurações!"
    exit 1
fi

log "Backup de configurações concluído"

# Backup das trends dos últimos 15 dias
log "Fazendo backup das trends (últimos 15 dias)..."
mysql -u${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_DB} -N -e \
    "SELECT 'trends' as table_name, COUNT(*) as records FROM trends WHERE clock >= ${CUTOFF_TIMESTAMP}
     UNION ALL
     SELECT 'trends_uint', COUNT(*) FROM trends_uint WHERE clock >= ${CUTOFF_TIMESTAMP};" \
    | tee -a ${LOG_FILE}

mysqldump -u${MYSQL_USER} -p${MYSQL_PASS} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    ${MYSQL_DB} trends trends_uint \
    --where="clock >= ${CUTOFF_TIMESTAMP}" > ${BACKUP_TRENDS} 2>> ${LOG_FILE}

if [ $? -ne 0 ]; then
    log "ERRO: Falha ao fazer backup das trends!"
    exit 1
fi

log "Backup de trends concluído"

# Backup dos scripts externos
log "Fazendo backup dos scripts externos..."
SCRIPTS_TO_BACKUP=""

if [ -d "${EXTERNALSCRIPTS_PATH}" ]; then
    log "  [OK] ExternalScripts encontrado: ${EXTERNALSCRIPTS_PATH}"
    SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${EXTERNALSCRIPTS_PATH}"
else
    log "  [AVISO] ExternalScripts não encontrado em: ${EXTERNALSCRIPTS_PATH}"
fi

if [ -d "${ALERTSCRIPTS_PATH}" ]; then
    log "  [OK] AlertScripts encontrado: ${ALERTSCRIPTS_PATH}"
    SCRIPTS_TO_BACKUP="${SCRIPTS_TO_BACKUP} ${ALERTSCRIPTS_PATH}"
else
    log "  [AVISO] AlertScripts não encontrado em: ${ALERTSCRIPTS_PATH}"
fi

if [ -n "${SCRIPTS_TO_BACKUP}" ]; then
    tar -czf ${BACKUP_SCRIPTS} ${SCRIPTS_TO_BACKUP} 2>> ${LOG_FILE}
    
    if [ $? -eq 0 ]; then
        SCRIPTS_SIZE=$(du -h ${BACKUP_SCRIPTS} | cut -f1)
        log "  [OK] Backup de scripts concluído: ${SCRIPTS_SIZE}"
    else
        log "  [ERRO] Falha ao fazer backup dos scripts!"
    fi
else
    log "  [AVISO] Nenhum diretório de scripts encontrado para backup"
    rm -f ${BACKUP_SCRIPTS}
fi

# Compactar dumps SQL
log "Compactando backups SQL..."
gzip ${BACKUP_CONFIG}
gzip ${BACKUP_TRENDS}

# Combinar em arquivo único
log "Combinando arquivos..."
BACKUP_FINAL="${BACKUP_DIR}/backup_${DATE}.tar.gz"

# Criar tar com todos os componentes
tar -czf ${BACKUP_FINAL} \
    -C ${BACKUP_DIR} backup_config_${DATE}.sql.gz \
    -C ${BACKUP_DIR} backup_trends_${DATE}.sql.gz \
    $([ -f ${BACKUP_SCRIPTS} ] && echo "-C ${BACKUP_DIR} backup_scripts_${DATE}.tar.gz") \
    2>> ${LOG_FILE}

# Limpar arquivos temporários
rm -f ${BACKUP_CONFIG}.gz ${BACKUP_TRENDS}.gz ${BACKUP_SCRIPTS}

SIZE=$(du -h ${BACKUP_FINAL} | cut -f1)
log "Tamanho do backup final: ${SIZE}"
log "Arquivo: ${BACKUP_FINAL}"

# Remover backups locais antigos - manter apenas os N últimos
log "Mantendo apenas os ${RETENTION_COUNT_LOCAL} backups mais recentes localmente..."
BACKUP_COUNT=$(ls -t ${BACKUP_DIR}/backup_*.tar.gz 2>/dev/null | wc -l)

if [ ${BACKUP_COUNT} -gt ${RETENTION_COUNT_LOCAL} ]; then
    log "Encontrados ${BACKUP_COUNT} backups, removendo os mais antigos..."
    ls -t ${BACKUP_DIR}/backup_*.tar.gz | tail -n +$((RETENTION_COUNT_LOCAL + 1)) | xargs rm -f
    log "[OK] Backups antigos removidos. Mantidos os ${RETENTION_COUNT_LOCAL} mais recentes."
else
    log "Total de ${BACKUP_COUNT} backups. Nenhum backup removido."
fi

log "=== Backup local concluído com sucesso ==="

# Upload SFTP (se habilitado)
if [ "$SFTP_ENABLED" = true ]; then
    log "=== Iniciando envio para servidor SFTP ==="
    
    # Verificar se sshpass está instalado
    if ! command -v sshpass &> /dev/null; then
        log "AVISO: sshpass não está instalado! Backup não será enviado para SFTP"
        log "Para instalar: apt-get install sshpass (Debian/Ubuntu) ou yum install sshpass (CentOS/RHEL)"
    else
        # Criar arquivo de comandos SFTP
        SFTP_BATCH="/tmp/sftp_upload_$$.txt"
        cat > ${SFTP_BATCH} << EOFBATCH
cd ${SFTP_DIR}
put ${BACKUP_FINAL}
ls -lh backup_${DATE}.tar.gz
bye
EOFBATCH
        
        # Enviar via SFTP
        log "Enviando ${BACKUP_FINAL} para ${SFTP_HOST}:${SFTP_DIR}..."
        sshpass -p "${SFTP_PASS}" sftp -P ${SFTP_PORT} -oBatchMode=no -b ${SFTP_BATCH} ${SFTP_USER}@${SFTP_HOST} >> ${LOG_FILE} 2>&1
        
        if [ $? -eq 0 ]; then
            log "[OK] Backup enviado com sucesso para SFTP: ${SFTP_HOST}"
            
            # Limpar backups antigos no SFTP
            log "Limpando backups remotos com mais de ${SFTP_RETENTION_DAYS} dias..."
            
            sshpass -p "${SFTP_PASS}" ssh -p ${SFTP_PORT} ${SFTP_USER}@${SFTP_HOST} << EOFSSH >> ${LOG_FILE} 2>&1
cd ${SFTP_DIR}
find . -name "backup_*.tar.gz" -mtime +${SFTP_RETENTION_DAYS} -delete
echo "Backups antigos removidos"
EOFSSH
            
            if [ $? -eq 0 ]; then
                log "[OK] Limpeza de backups remotos concluída"
            else
                log "[AVISO] Não foi possível limpar backups remotos antigos"
            fi
            
        else
            log "[ERRO] Falha ao enviar backup para SFTP!"
        fi
        
        # Limpar arquivo temporário
        rm -f ${SFTP_BATCH}
    fi
    
    log "=== Envio para SFTP concluído ==="
fi

log "=== Processo completo finalizado ==="

exit 0