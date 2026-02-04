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
- Upload automático para servidor SFTP/FTP
- Gerenciamento de retenção de backups (local e remoto)

## 🎯 Por que usar estes scripts?

### Problema
Backups completos do Zabbix podem atingir centenas de GB devido às tabelas de histórico (`history`, `history_uint`, `history_str`, `history_text`, `history_log`), tornando o processo lento, custoso em armazenamento e inviável para restaurações rápidas.

### Solução
Estes scripts implementam backup seletivo:
- **Configurações**: Todas as tabelas de configuração (hosts, templates, triggers, items, mapas, dashboards, usuários, etc.)
- **Trends**: Apenas dados agregados de 1 hora dos últimos 15 dias (suficiente para análises e gráficos)
- **Scripts**: Backup completo de externalscripts e alertscripts personalizados
- **History**: Excluído do backup (dados brutos de histórico não são preservados)

Esta abordagem reduz o tamanho do backup em até 95% e permite restaurações completas da configuração em minutos.

## 🐳 Zabbix Backup Docker

### Características
- Execução de mysqldump através do `docker exec` no container MySQL/MariaDB
- Suporte a ambientes Docker Compose e Docker standalone
- Não requer acesso direto ao MySQL (funciona via container)

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

## 💻 Zabbix Backup Local

### Características
- Execução direta de mysqldump no servidor MySQL/MariaDB
- Ideal para instalações tradicionais do Zabbix
- Suporte a instalações via pacote (.deb, .rpm) ou compiladas

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

## 📦 Estrutura do Backup

Cada execução gera um arquivo `.tar.gz` contendo:
```
backup_YYYYMMDD_HHMMSS.tar.gz
├── backup_config_YYYYMMDD_HHMMSS.sql.gz    # Configurações completas
├── backup_trends_YYYYMMDD_HHMMSS.sql.gz    # Trends dos últimos 15 dias
└── backup_scripts_YYYYMMDD_HHMMSS.tar.gz   # Scripts externos
```

### Tamanhos típicos

| Componente | Tamanho Aproximado |
|------------|-------------------|
| Configurações | 5-50 MB |
| Trends (15 dias) | 10-100 MB |
| Scripts | < 1 MB |
| **Total** | **15-150 MB** |

*Comparado a 50-500 GB de um backup completo com history*

## 🔍 Validação de Backup

### Método rápido
```bash
# Listar conteúdo
tar -tzf backup_20260203_151033.tar.gz

# Extrair para validação
mkdir /tmp/validar_backup
tar -xzf backup_20260203_151033.tar.gz -C /tmp/validar_backup

# Verificar integridade dos SQL
cd /tmp/validar_backup
gzip -t backup_config_*.sql.gz && echo "[OK] Config"
gzip -t backup_trends_*.sql.gz && echo "[OK] Trends"

# Ver tabelas no backup
zcat backup_config_*.sql.gz | grep "CREATE TABLE" | cut -d'`' -f2

# Verificar período das trends
zcat backup_trends_*.sql.gz | grep -oP '\([0-9]{10},' | head -3 | while read ts; do
    timestamp=$(echo $ts | tr -d '(,')
    date -d @$timestamp '+%Y-%m-%d %H:%M:%S'
done

# Listar scripts
tar -tzf backup_scripts_*.tar.gz
```

## 🔄 Restauração

### 1. Restaurar Configurações
```bash
# Extrair backup
tar -xzf backup_20260203_151033.tar.gz

# Restaurar configurações
zcat backup_config_20260203_151033.sql.gz | mysql -uzabbix -p zabbix

# Restaurar trends
zcat backup_trends_20260203_151033.sql.gz | mysql -uzabbix -p zabbix
```

### 2. Restaurar Scripts
```bash
# Extrair scripts do backup
tar -xzf backup_scripts_20260203_151033.tar.gz

# Restaurar para os locais originais
cp -r externalscripts/* /usr/lib/zabbix/externalscripts/
cp -r alertscripts/* /usr/lib/zabbix/alertscripts/

# Ajustar permissões
chown -R zabbix:zabbix /usr/lib/zabbix/externalscripts
chown -R zabbix:zabbix /usr/lib/zabbix/alertscripts
chmod +x /usr/lib/zabbix/externalscripts/*
chmod +x /usr/lib/zabbix/alertscripts/*
```

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
[2026-02-03 15:10:33] === Iniciando backup otimizado do Zabbix ===
[2026-02-03 15:10:33] Fazendo backup de trends desde: 2026-01-19 15:10:33
[2026-02-03 15:10:39] Backup de configurações concluído
[2026-02-03 15:10:40] Backup de trends concluído
[2026-02-03 15:10:40] [OK] ExternalScripts encontrado
[2026-02-03 15:10:41] Tamanho do backup final: 6.8M
[2026-02-03 15:10:41] [OK] Backup enviado com sucesso para SFTP
```

## ⚠️ Considerações Importantes

### O que NÃO está no backup
- **Dados de histórico bruto** (tabelas `history*`): Estes dados consomem 90-95% do espaço do banco e não são essenciais para restauração de configuração
- **Eventos antigos**: Apenas trends agregados de 15 dias são preservados

### Quando usar backup completo
Para disaster recovery com preservação total de histórico, considere:
- Snapshots de VM/LVM
- Replicação de banco de dados (MySQL replication)
- Backup incremental do MySQL com binlogs

### Segurança
- **NUNCA commite senhas no Git**: Use variáveis de ambiente ou arquivos de configuração externos
- Proteja os arquivos de backup com permissões adequadas: `chmod 600`
- Criptografe backups sensíveis: `gpg --encrypt backup.tar.gz`

## 🤝 Contribuindo

Melhorias e sugestões são bem-vindas! Para contribuir:

1. Fork este repositório
2. Crie uma branch para sua feature (`git checkout -b feature/melhoria`)
3. Commit suas mudanças (`git commit -m 'Adiciona melhoria X'`)
4. Push para a branch (`git push origin feature/melhoria`)
5. Abra um Pull Request

## 📝 Licença

MIT License - Sinta-se livre para usar e modificar conforme necessário.

## 🔗 Recursos Adicionais

- [Documentação Oficial Zabbix - Backup](https://www.zabbix.com/documentation/current/manual/installation/requirements/best_practices)
- [MySQL Backup Best Practices](https://dev.mysql.com/doc/mysql-backup-excerpt/en/)
- [Zabbix Database Partitioning](https://www.zabbix.com/documentation/current/manual/appendix/install/db_scripts)

---

**Desenvolvido por**: Felipe Hoher  
**Última atualização**: Fevereiro 2026
