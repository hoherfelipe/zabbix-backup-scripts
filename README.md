# Zabbix Backup Scripts

Scripts otimizados para backup automatizado de instâncias Zabbix, suportando ambientes Docker e instalações locais tradicionais.

## 📋 Visão Geral

Esta coleção contém dois scripts de backup desenvolvidos para diferentes cenários de deploy do Zabbix:

- **`zabbix-backup-docker.sh`**: Para ambientes Zabbix containerizados (Docker/Podman)
- **`zabbix-backup-local.sh`**: Para instalações tradicionais do Zabbix (bare metal/VM)

Ambos os scripts implementam estratégias otimizadas de backup, focando em:
- Preservação de configurações completas do Zabbix
- Retenção apenas de dados de tendências (trends) dos últimos 15 dias
- Exclusão de tabelas de histórico (history) que consomem grande espaço
- Backup de scripts externos (externalscripts e alertscripts)
- **Backup dos arquivos de configuração** (docker-compose.yml ou zabbix_server.conf)
- Upload automático para servidor SFTP/FTP
- Gerenciamento de retenção de backups (local e remoto)
- **Monitoramento de status via Zabbix Agent** (arquivo JSON + template)

## 🎯 Por que usar estes scripts?

### Problema
Backups completos do Zabbix podem atingir centenas de GB devido às tabelas de histórico (`history`, `history_uint`, `history_str`, `history_text`, `history_log`), tornando o processo lento, custoso em armazenamento e inviável para restaurações rápidas.

### Solução
Estes scripts implementam backup seletivo:
- **Configurações**: Todas as tabelas de configuração (hosts, templates, triggers, items, mapas, dashboards, usuários, etc.)
- **Trends**: Apenas dados agregados de 1 hora dos últimos 15 dias (suficiente para análises e gráficos)
- **Scripts**: Backup completo de externalscripts e alertscripts personalizados
- **Arquivos de configuração**: docker-compose.yml (Docker) ou zabbix_server.conf (Local) — essenciais para restauração completa em caso de perda total da VM
- **History**: Excluído do backup (dados brutos de histórico não são preservados)

Esta abordagem reduz o tamanho do backup em até 95% e permite restaurações completas da configuração em minutos.

---

## 📦 Estrutura do Backup

Cada execução gera um arquivo `.tar.gz` contendo:
```
backup_YYYYMMDD_HHMMSS.tar.gz
├── backup_config_YYYYMMDD_HHMMSS.sql.gz     # Configurações completas do banco
├── backup_trends_YYYYMMDD_HHMMSS.sql.gz     # Trends dos últimos 15 dias
├── backup_scripts_YYYYMMDD_HHMMSS.tar.gz    # Scripts externos (externalscripts + alertscripts)
└── backup_configs_YYYYMMDD_HHMMSS.tar.gz    # Arquivos de configuração (compose/zabbix_server.conf)
```

### Tamanhos típicos

| Componente | Tamanho Aproximado |
|------------|-------------------|
| Configurações SQL | 5–50 MB |
| Trends (15 dias) | 10–100 MB |
| Scripts | < 1 MB |
| Arquivos de configuração | < 1 MB |
| **Total** | **15–150 MB** |

*Comparado a 50–500 GB de um backup completo com history*

---

## 🐳 Zabbix Backup Docker

### Características
- Execução de mysqldump através do `docker exec` no container MySQL/MariaDB
- Suporte a ambientes Docker Compose e Docker standalone
- Não requer acesso direto ao MySQL (funciona via container)
- Backup automático do `docker-compose.yml` para preservar credenciais e configurações

### Pré-requisitos
```bash
# Debian/Ubuntu
apt-get install -y sshpass gzip tar

# CentOS/RHEL
yum install -y epel-release
yum install -y sshpass gzip tar
```

### Configuração

Edite as variáveis no início do script:
```bash
# Container Docker
DOCKER_CONTAINER="zabbix-mysql-server"                      # Nome do container MySQL

# Credenciais do banco
MYSQL_USER="USUARIO"
MYSQL_PASS="SENHA"
MYSQL_DB="NOME_DO_BANCO"

# Caminhos dos scripts (no host, não no container)
EXTERNALSCRIPTS_PATH="/docker/zabbix/externalscripts"
ALERTSCRIPTS_PATH="/docker/zabbix/alertscripts"

# Arquivos de configuração para backup
COMPOSE_FILE="/docker/fb-zabbix/docker-compose.yml"         # docker-compose.yml
EXTRA_CONFIG_FILES=""                                        # Outros arquivos separados por espaço
                                                             # Ex: "/etc/hosts /etc/timezone"

# Backup local
BACKUP_DIR="/opt/backup/zabbix"
RETENTION_COUNT_LOCAL=2                                     # Manter apenas os 2 últimos localmente

# SFTP (opcional)
SFTP_ENABLED=true                                           # true para ativar, false para desativar
SFTP_HOST="IP_FTP"
SFTP_PORT="PORTA_FTP"
SFTP_USER="USUARIO_FTP"
SFTP_PASS="SENHA_FTP"
SFTP_DIR="/opt/bkp_zabbix"
SFTP_RETENTION_DAYS=5                                       # Retenção no servidor remoto
```

### Uso
```bash
# Dar permissão de execução
chmod +x zabbix-backup-docker.sh

# Executar manualmente
./zabbix-backup-docker.sh

# Agendar no cron (diariamente às 2h da manhã)
crontab -e
# Adicionar:
0 2 * * * /caminho/para/zabbix-backup-docker.sh >> /var/log/backup_zabbix_docker.log 2>&1
```

---

## 💻 Zabbix Backup Local

### Características
- Execução direta de mysqldump no servidor MySQL/MariaDB
- Ideal para instalações tradicionais do Zabbix
- Suporte a instalações via pacote (.deb, .rpm) ou compiladas
- Backup automático do `zabbix_server.conf` para preservar credenciais e configurações

### Pré-requisitos
```bash
# Debian/Ubuntu
apt-get install -y mysql-client sshpass gzip tar

# CentOS/RHEL
yum install -y mysql mariadb sshpass gzip tar
```

### Configuração

Edite as variáveis no início do script:
```bash
# Credenciais do banco
MYSQL_USER="USUARIO"
MYSQL_PASS="SENHA"
MYSQL_DB="NOME_DO_BANCO"

# Caminhos padrão dos scripts (ajustar conforme instalação)
EXTERNALSCRIPTS_PATH="/usr/lib/zabbix/externalscripts"
ALERTSCRIPTS_PATH="/usr/lib/zabbix/alertscripts"

# Arquivos de configuração para backup
ZABBIX_SERVER_CONF="/etc/zabbix/zabbix_server.conf"         # Conf do Zabbix Server
EXTRA_CONFIG_FILES=""                                        # Outros arquivos separados por espaço
                                                             # Ex: "/etc/zabbix/zabbix_agentd.conf"

# Backup local
BACKUP_DIR="/opt/backup/zabbix"
RETENTION_COUNT_LOCAL=2

# SFTP (opcional)
SFTP_ENABLED=true
SFTP_HOST="IP_FTP"
SFTP_PORT="PORTA_FTP"
SFTP_USER="USUARIO_FTP"
SFTP_PASS="senha_sftp"
SFTP_DIR="/opt/bkp_zabbix"
SFTP_RETENTION_DAYS=10
```

### Encontrar caminhos dos scripts
```bash
# Verificar configuração do Zabbix Server
grep -E "ExternalScripts|AlertScriptsPath" /etc/zabbix/zabbix_server.conf

# Localizar manualmente
find /usr -name externalscripts 2>/dev/null
find /usr -name alertscripts 2>/dev/null
```

### Uso
```bash
# Dar permissão de execução
chmod +x zabbix-backup-local.sh

# Executar manualmente
./zabbix-backup-local.sh

# Agendar no cron (diariamente às 2h da manhã)
crontab -e
# Adicionar:
0 2 * * * /caminho/para/zabbix-backup-local.sh >> /var/log/backup_zabbix.log 2>&1
```

---

## 📊 Comparação: Docker vs Local

| Feature | Docker | Local |
|---------|--------|-------|
| **Acesso MySQL** | `docker exec` no container | Conexão direta ao MySQL |
| **Validação de Container** | ✅ Verifica se existe e está rodando | ❌ Não aplicável |
| **Health Check MySQL** | ✅ Aguarda MySQL ficar pronto | ❌ Assume disponibilidade |
| **`--no-tablespaces`** | ✅ Incluído | ✅ Incluído |
| **Backup de configuração** | ✅ docker-compose.yml | ✅ zabbix_server.conf |
| **Arquivos extras** | ✅ `EXTRA_CONFIG_FILES` | ✅ `EXTRA_CONFIG_FILES` |
| **Dependências** | Docker + sshpass | mysql-client + sshpass |
| **Ideal para** | Ambientes containerizados | VMs, bare metal, pacotes |

---

## 📡 Monitoramento via Zabbix

Os scripts integram-se ao Zabbix para monitoramento automático do status de backup. A solução é composta por três partes: o arquivo de status JSON gerado pelo script, a coleta via Zabbix Agent e o template com itens e triggers.

### 1. Arquivo de status

O script grava `/var/log/zabbix_backup_status.json` ao final de cada execução (sucesso ou erro). Este arquivo é sempre sobrescrito com o resultado mais recente e tem permissão `644` para leitura pelo agente.

```json
{
  "status": "OK",
  "timestamp": "2026-03-19 02:00:01",
  "message": "Backup concluído com sucesso"
}
```

Em caso de falha, o campo `status` passa para `"ERRO"` com a etapa específica:

```json
{
  "status": "ERRO",
  "timestamp": "2026-03-19 02:05:12",
  "message": "Falha ao enviar backup para SFTP - 10.10.10.5"
}
```

### Pontos de falha mapeados

| Mensagem | Causa |
|---|---|
| `Container 'X' não encontrado` | Container Docker do MySQL não existe |
| `Container 'X' não está rodando` | Container Docker parado |
| `MySQL não ficou disponível após N tentativas` | MySQL não respondeu após reinicialização |
| `Falha no mysqldump - backup de configurações` | Erro no dump das tabelas de configuração |
| `Falha no mysqldump - backup de trends` | Erro no dump das tabelas de trends |
| `Falha ao compactar arquivos SQL` | Erro no gzip dos dumps |
| `Falha ao combinar arquivos no tar final` | Erro ao montar o tar.gz final |
| `sshpass não está instalado - backup não enviado para SFTP` | sshpass ausente no servidor |
| `Falha ao enviar backup para SFTP - <IP>` | Falha na transferência SFTP |
| `Backup concluído com sucesso` | Tudo OK |

### 2. Configuração do Zabbix Agent

Crie o arquivo de UserParameter no servidor monitorado:

```bash
cat > /etc/zabbix/zabbix_agentd.d/backup_status.conf << 'EOF'
UserParameter=backup.status,cat /var/log/zabbix_backup_status.json 2>/dev/null || echo '{"status":"ERRO","timestamp":"N/A","message":"Arquivo de status nao encontrado"}'
EOF

systemctl restart zabbix-agent
```

Verificar se está respondendo:
```bash
/usr/sbin/zabbix_agentd -t backup.status
```

### 3. Template Zabbix

O arquivo `Template_Backup_Zabbix_Status.yaml` contém o template pronto para importação no Zabbix 7.2.

#### Importação

1. Acesse **Configuration → Templates → Import**
2. Selecione o arquivo `Template_Backup_Zabbix_Status.yaml`
3. Confirme a importação
4. Vincule o template ao host monitorado em **Configuration → Hosts → [host] → Templates**

#### Itens coletados

| Item | Chave | Tipo | Descrição |
|------|-------|------|-----------|
| Backup Zabbix - Status JSON | `backup.status` | Zabbix Agent (Ativo) | JSON completo — item master |
| Backup Zabbix - Status | `backup.status.result` | Dependente | `OK` ou `ERRO` |
| Backup Zabbix - Timestamp | `backup.status.timestamp` | Dependente | Data/hora da última execução |
| Backup Zabbix - Timestamp Unix | `backup.status.timestamp.unix` | Dependente | Timestamp Unix — base para cálculo de atraso |
| Backup Zabbix - Mensagem | `backup.status.message` | Dependente | Mensagem detalhada do resultado |

#### Triggers configuradas

| Trigger | Severidade | Condição |
|---------|-----------|----------|
| Backup Zabbix com ERRO em `{HOST.NAME}` | Alta | `status != "OK"` |
| Backup Zabbix não executado há mais de 26h em `{HOST.NAME}` | Alta | Tempo decorrido > 93600 segundos |

---

## 🔄 Restauração

Para o processo completo de restauração, consulte o manual `Manual - Restore de Backup Zabbix.md`.

### Restauração rápida — Zabbix Local

```bash
# Extrair backup
tar -xzf backup_20260319_020001.tar.gz

# Recriar banco
mysql -uroot -e "DROP DATABASE zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost'; FLUSH PRIVILEGES;"

# Importar configurações
zcat backup_config_*.sql.gz | mysql --default-character-set=utf8mb4 -uroot zabbix

# Importar trends
zcat backup_trends_*.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -pzabbix zabbix

# Restaurar arquivos de configuração
tar -xzf backup_configs_*.tar.gz -C /
```

### Restauração rápida — Zabbix Docker

```bash
# Extrair backup
tar -xzf backup_20260319_020001.tar.gz

# Recriar banco
docker exec zabbix-mysql mysql -uroot -pROOT_PASS -e \
  "DROP DATABASE zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%'; FLUSH PRIVILEGES;"

# Importar configurações (usar root para evitar erro de permissão SUPER)
zcat backup_config_*.sql.gz | docker exec -i zabbix-mysql mysql --default-character-set=utf8mb4 -uroot -pROOT_PASS zabbix

# Importar trends
zcat backup_trends_*.sql.gz | docker exec -i zabbix-mysql mysql --default-character-set=utf8mb4 -uroot -pROOT_PASS zabbix

# Restaurar arquivos de configuração
tar -xzf backup_configs_*.tar.gz -C /

# Reiniciar Zabbix Server
docker restart zabbix-server
```

---

## 📊 Logs

Ambos os scripts geram logs detalhados:
```bash
# Docker
tail -f /var/log/backup_zabbix_docker.log

# Local
tail -f /var/log/backup_zabbix.log
```

Exemplo de log:
```
[2026-03-19 02:00:01] === Iniciando backup otimizado do Zabbix ===
[2026-03-19 02:00:01] Fazendo backup de trends desde: 2026-03-04 02:00:01
[2026-03-19 02:00:07] Backup de configurações concluído
[2026-03-19 02:00:09] Backup de trends concluído
[2026-03-19 02:00:09]   ✓ ExternalScripts encontrado: /usr/lib/zabbix/externalscripts
[2026-03-19 02:00:09]   ✓ Backup de scripts concluído: 12K
[2026-03-19 02:00:09]   ✓ zabbix_server.conf encontrado: /etc/zabbix/zabbix_server.conf
[2026-03-19 02:00:09]   ✓ Backup de configurações concluído: 4.0K
[2026-03-19 02:00:10] Tamanho do backup final: 6.8M
[2026-03-19 02:00:11] ✓ Backup enviado com sucesso para SFTP: 10.10.10.5
```

---

## 🔧 Troubleshooting

### Erro: `Access denied; you need SUPER or SET_USER_ID`
O dump contém `DEFINER` em views ou procedures. Use root na importação:
```bash
zcat backup_config_*.sql.gz | mysql --default-character-set=utf8mb4 -uroot zabbix
```

### Erro: `Table 'zabbix.auditlog' doesn't exist`
O backup exclui `auditlog` e `history` por padrão. Ao restaurar em Zabbix local, o servidor tentará criar um índice nessa tabela. Crie a tabela vazia antes de iniciar o servidor — consulte o manual de restore para o script completo.

### Erro: `Container not found`
```bash
docker ps -a --format '{{.Names}}'
# Ajuste DOCKER_CONTAINER no script com o nome correto
```

### Erro: `Permission denied` no SFTP
```bash
# Senhas com caracteres especiais: SEMPRE use aspas simples
SFTP_PASS='senha#especial@123'
```

### Erro: `sshpass: command not found`
```bash
apt-get install -y sshpass          # Debian/Ubuntu
yum install -y epel-release sshpass # CentOS/RHEL
```

### Zabbix Server não inicia após restore (Docker)
```bash
docker logs zabbix-server --tail 30
# Se houver erro de upgrade de schema, aguardar — o servidor aplica patches automaticamente
# Se tabela auditlog não existir, consultar o manual de restore
```

---

## ⚠️ Considerações Importantes

### Segurança dos arquivos de configuração
- O `docker-compose.yml` e o `zabbix_server.conf` contêm **senhas em texto puro**
- Os backups são enviados para o SFTP — garanta que o servidor SFTP tenha acesso restrito
- Considere criptografar os backups se o ambiente exigir: `gpg --encrypt backup.tar.gz`
- **NUNCA commite os scripts com senhas reais no Git** — use variáveis de ambiente ou arquivos externos

### Caracteres especiais em senhas
- **SEMPRE use aspas simples** para senhas com caracteres especiais:
  ```bash
  SFTP_PASS='M003|CE1BVq_h4f:'   # ✅ Correto
  SFTP_PASS="M003|CE1BVq_h4f:"   # ❌ Pode falhar
  ```

### O que NÃO está no backup
- **Dados de histórico bruto** (tabelas `history*`): consomem 90–95% do espaço
- **Tabela auditlog**: excluída por tamanho — recriada vazia no restore
- **Eventos antigos**: apenas trends agregados de 15 dias são preservados

### Quando usar backup completo
Para disaster recovery com preservação total de histórico, considere:
- Snapshots de VM/LVM
- Replicação de banco de dados (MySQL replication)
- Backup incremental do MySQL com binlogs

---

## 🔗 Recursos Adicionais

- [Documentação Oficial Zabbix - Backup](https://www.zabbix.com/documentation/current/manual/installation/requirements/best_practices)
- [MySQL Backup Best Practices](https://dev.mysql.com/doc/mysql-backup-excerpt/en/)
- [Zabbix Database Partitioning](https://www.zabbix.com/documentation/current/manual/appendix/install/db_scripts)

---

**Desenvolvido por**: Felipe Hoher  
**Empresa**: FB Consultoria  
**Última atualização**: Março 2026