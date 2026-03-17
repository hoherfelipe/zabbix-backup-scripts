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

## 📊 Comparação: Docker vs Local

| Feature | Docker | Local |
|---------|--------|-------|
| **Acesso MySQL** | `docker exec` no container | Conexão direta ao MySQL |
| **Validação de Container** | ✅ Verifica se existe e está rodando | ❌ Não aplicável |
| **Health Check MySQL** | ✅ Aguarda MySQL ficar pronto | ❌ Assume disponibilidade |
| **`--no-tablespaces`** | ✅ Incluído | ✅ Incluído |
| **Dependências** | Docker + sshpass | mysql-client + sshpass |
| **Ideal para** | Ambientes containerizados | VMs, bare metal, pacotes |

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
## 🔧 Troubleshooting

### Problemas Comuns - Docker

**Erro: "Container not found"**
```bash
# Listar containers disponíveis
docker ps -a

# Verificar nome exato do container MySQL
docker ps --format '{{.Names}}' | grep -i mysql

# Ajustar variável DOCKER_CONTAINER no script
vim zabbix-backup-docker.sh
# Linha 10: DOCKER_CONTAINER="nome_correto_do_container"
```

**Erro: "Lost connection to MySQL server"**
- Container MySQL acabou de reiniciar
- Script aguarda automaticamente até 30 segundos
- Se precisar mais tempo, ajuste `MAX_ATTEMPTS=15` para valor maior
- Cada tentativa aguarda 2 segundos

**Erro: "Container is not running"**
```bash
# Verificar status do container
docker ps -a | grep mysql

# Iniciar container se estiver parado
docker start nome_do_container
```

---

### Problemas Comuns - Ambos os Scripts

**Erro: "Access denied... PROCESS privilege"**

Solução 1 - Usar `--no-tablespaces` (já incluído nos scripts):
```bash
# Os scripts já incluem esta flag por padrão
# Verifique se está presente nos comandos mysqldump
grep "no-tablespaces" zabbix-backup*.sh
```

Solução 2 - Conceder permissão PROCESS:
```bash
mysql -u root -p
GRANT PROCESS ON *.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
```

**Erro: "Permission denied" no SFTP**
```bash
# 1. Verificar credenciais
sftp -P [PORTA] usuario@servidor_ftp
# Digite a senha quando solicitado

# 2. Verificar se diretório existe no servidor FTP
ssh -p [PORTA] usuario@servidor_ftp "ls -ld /opt/bkp_zabbix"

# 3. Criar diretório se não existir
ssh -p [PORTA] usuario@servidor_ftp "mkdir -p /opt/bkp_zabbix && chmod 755 /opt/bkp_zabbix"

# 4. Senhas com caracteres especiais - usar aspas simples
# ✅ CORRETO:   SFTP_PASS='M003|CE1BVq_h4f:'
# ❌ INCORRETO: SFTP_PASS="M003|CE1BVq_h4f:"
```

**Erro: "sshpass: command not found"**
```bash
# Debian/Ubuntu
apt-get update && apt-get install -y sshpass

# CentOS/RHEL
yum install -y epel-release
yum install -y sshpass
```

**Backup muito grande ou muito demorado**
```bash
# Ajustar período de retenção dos trends (padrão: 15 dias)
vim zabbix-backup*.sh
# Linha ~22: TRENDS_RETENTION_DAYS=7  # Reduzir para 7 dias

# Verificar tamanho das tabelas trends
mysql -u zabbix -p zabbix -e "
SELECT 
    table_name,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Tamanho_MB',
    table_rows AS 'Linhas'
FROM information_schema.TABLES
WHERE table_schema = 'zabbix' 
AND table_name LIKE 'trends%'
ORDER BY (data_length + index_length) DESC;
"
```

**Caracteres estranhos no log (encoding)**
```bash
# Verificar encoding do sistema
locale

# Instalar locale pt_BR se necessário
apt-get install -y locales
dpkg-reconfigure locales

# Forçar UTF-8 no script
export LANG=pt_BR.UTF-8
```

---

### Testando o Script

**Teste básico antes de agendar no cron:**
```bash
# 1. Executar manualmente
bash -x zabbix-backup.sh 2>&1 | tee /tmp/test_backup.log

# 2. Verificar se gerou arquivo de backup
ls -lh /opt/backup/zabbix/

# 3. Validar integridade
tar -tzf /opt/backup/zabbix/backup_*.tar.gz

# 4. Verificar log
tail -100 /var/log/backup_zabbix*.log

# 5. Testar envio FTP (se habilitado)
# Verificar se arquivo chegou no servidor remoto
ssh -p [PORTA] usuario@servidor_ftp "ls -lh /opt/bkp_zabbix/"
```

## ⚠️ Considerações Importantes

### Permissões MySQL
- Os scripts usam `--no-tablespaces` para evitar erro de permissão `PROCESS`
- Esta flag é compatível com MySQL 5.7+ e MariaDB 10.2+
- Se seu usuário MySQL tiver permissão `PROCESS`, esta flag continua funcionando normalmente
- Recomendado manter `--no-tablespaces` para compatibilidade universal

### Caracteres Especiais em Senhas
- **SEMPRE use aspas simples** para senhas com caracteres especiais: `PASS='senha#123'`
- Aspas duplas podem causar interpretação incorreta de caracteres como `$`, `#`, `@`, `!`
- Exemplos de caracteres que exigem aspas simples: `# $ @ ! ^ & * ( ) | \ ' " ;`

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
