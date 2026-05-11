#!/bin/bash
# scripts/configure-ssl.sh
# Скрипт для настройки SSL в PostgreSQL 18.3 (Debian)
# Выполняется из /docker-entrypoint-initdb.d/

set -e

echo "=== Настройка SSL для PostgreSQL (Debian) ==="

# Ждём инициализации PostgreSQL
MAX_RETRIES=30
RETRY_COUNT=0

until [ -f "$PGDATA/postgresql.conf" ] && [ -f "$PGDATA/PG_VERSION" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Ошибка: PostgreSQL не инициализировался"
        exit 1
    fi
    echo "Ожидание инициализации PostgreSQL... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo "PostgreSQL инициализирован"

# Проверяем сертификаты
CERT_DIR="/etc/postgresql/certs"

if [ ! -f "$CERT_DIR/server.crt" ] || \
   [ ! -f "$CERT_DIR/server.key" ] || \
   [ ! -f "$CERT_DIR/ca.crt" ]; then
    echo "❌ SSL-сертификаты не найдены в $CERT_DIR"
    ls -la "$CERT_DIR/" || true
    exit 1
fi

echo "Сертификаты найдены:"
ls -la "$CERT_DIR/"

# Устанавливаем правильные права
chmod 600 "$CERT_DIR/server.key"
chown postgres:postgres "$CERT_DIR/server.crt" "$CERT_DIR/server.key" "$CERT_DIR/ca.crt"

# Функция обновления параметров
upsert_param() {
    local param=$1
    local value=$2
    local file="$PGDATA/postgresql.conf"
    
    local escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^[[:space:]]*${param}[[:space:]]*=" "$file"; then
        sed -i "s/^[[:space:]]*${param}[[:space:]]*=.*/${param} = ${escaped_value}/" "$file"
    elif grep -q "^[[:space:]]*#${param}[[:space:]]*=" "$file"; then
        sed -i "s/^[[:space:]]*#${param}[[:space:]]*=.*/${param} = ${escaped_value}/" "$file"
    else
        echo "${param} = ${escaped_value}" >> "$file"
    fi
}

# используем абсолютные пути
echo "Настройка SSL с абсолютными путями..."

upsert_param "ssl" "on"
upsert_param "ssl_ca_file" "'/etc/postgresql/certs/ca.crt'"
upsert_param "ssl_cert_file" "'/etc/postgresql/certs/server.crt'"
upsert_param "ssl_key_file" "'/etc/postgresql/certs/server.key'"
upsert_param "ssl_prefer_server_ciphers" "on"
upsert_param "ssl_ciphers" "'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256'"
upsert_param "ssl_min_protocol_version" "'TLSv1.2'"

# Логирование для отладки
upsert_param "log_connections" "on"
upsert_param "log_disconnections" "on"

echo "postgresql.conf настроен"

# Настройка pg_hba.conf
echo "🔍 Настройка pg_hba.conf..."

if [ -f /etc/postgresql/pg_hba.conf ]; then
    echo "Использование кастомного pg_hba.conf"
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    chown postgres:postgres "$PGDATA/pg_hba.conf"
else
    echo "Создание pg_hba.conf с поддержкой сертификатов..."
    
    cat > "$PGDATA/pg_hba.conf" << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Локальные подключения (для healthcheck)
local   all             all                                     trust

# SSL с проверкой клиентского сертификата
hostssl all             all             0.0.0.0/0               cert map=ssl_map
hostssl all             all             ::0/0                   cert map=ssl_map

# Резервный метод с паролем
# hostssl all           all             0.0.0.0/0               scram-sha-256
EOF
    chown postgres:postgres "$PGDATA/pg_hba.conf"
    echo "Создан pg_hba.conf"
fi

if [ -f /etc/postgresql/pg_ident.conf ]; then
    cp /etc/postgresql/pg_ident.conf "$PGDATA/pg_ident.conf"
    chown postgres:postgres "$PGDATA/pg_ident.conf"
fi

# Перезагружаем PostgreSQL для применения настроек
echo "Применение настроек..."
pg_ctl reload -D "$PGDATA" -s || {
    echo "PostgreSQL ещё не запущен, настройки применятся при старте"
}

echo "Итоговая конфигурация SSL:"
echo "----------------------------------------"
grep -E "^[[:space:]]*ssl" "$PGDATA/postgresql.conf" | grep -v "^[[:space:]]*#" || true
echo "----------------------------------------"
echo "Настройка SSL завершена!"
