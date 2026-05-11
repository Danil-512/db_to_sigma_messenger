#!/bin/bash
# scripts/generate-certs.sh
set -e

# Определяем директории относительно местоположения скрипта
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CERT_DIR="$SCRIPT_DIR/../certs"
CA_DIR="$CERT_DIR/ca"
SERVERS_DIR="$CERT_DIR/servers"
CLIENTS_DIR="$CERT_DIR/clients"

echo "=== Генерация сертификатов для PostgreSQL mTLS ==="
echo "Рабочая директория: $SCRIPT_DIR"
echo "Директория сертификатов: $CERT_DIR"

# Создаём структуру директорий
mkdir -p "$CA_DIR" "$SERVERS_DIR" "$CLIENTS_DIR"



# 1. Генерируем корневой CA
if [ ! -f "$CA_DIR/ca.key" ] || [ ! -s "$CA_DIR/ca.key" ]; then
    echo "Генерируем корневой CA..."
    
    # Приватный ключ CA (шифрованный паролем)
    openssl genrsa -aes256 -passout pass:ca-password-change-me -out "$CA_DIR/ca.key" 4096
    
    # Сертификат CA (срок 10 лет)
    openssl req -x509 -new -nodes \
        -key "$CA_DIR/ca.key" \
        -passin pass:ca-password-change-me \
        -sha256 -days 3650 \
        -out "$CA_DIR/ca.crt" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=Sigma/OU=Dev/CN=Sigma Internal CA"
    
    echo "Корневой CA создан!"
else
    echo "Корневой CA уже существует"
    # Проверяем размер файлов
    echo "   ca.key: $(wc -c < "$CA_DIR/ca.key") байт"
    echo "   ca.crt: $(wc -c < "$CA_DIR/ca.crt") байт"
fi



# 2. Функция генерации серверного сертификата
generate_server_cert() {
    local SERVICE=$1
    local CN=$2
    
    local SERVICE_DIR="$SERVERS_DIR/$SERVICE"
    
    if [ -f "$SERVICE_DIR/server.crt" ] && [ -s "$SERVICE_DIR/server.crt" ] && \
       [ -f "$SERVICE_DIR/server.key" ] && [ -s "$SERVICE_DIR/server.key" ]; then
        echo "Серверный сертификат для $SERVICE уже существует"
        return
    fi
    
    echo "Генерируем серверный сертификат для $SERVICE..."
    mkdir -p "$SERVICE_DIR"
    
    # Приватный ключ
    openssl genrsa -out "$SERVICE_DIR/server.key" 2048
    
    # Запрос на сертификат (CSR) с SAN
    cat > "$SERVICE_DIR/ext.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = Sigma
OU = DB
CN = $CN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
EOF
    
    # Генерируем CSR и сертификат за один проход
    openssl req -new -nodes \
        -key "$SERVICE_DIR/server.key" \
        -config "$SERVICE_DIR/ext.cnf" \
        -out "$SERVICE_DIR/server.csr"
    
    openssl x509 -req \
        -in "$SERVICE_DIR/server.csr" \
        -CA "$CA_DIR/ca.crt" \
        -CAkey "$CA_DIR/ca.key" \
        -passin pass:ca-password-change-me \
        -CAcreateserial \
        -out "$SERVICE_DIR/server.crt" \
        -days 365 \
        -sha256 \
        -extfile "$SERVICE_DIR/ext.cnf" \
        -extensions v3_req
    
    # Очистка
    rm "$SERVICE_DIR/server.csr" "$SERVICE_DIR/ext.cnf"
    
    # Копируем корневой сертификат
    cp "$CA_DIR/ca.crt" "$SERVICE_DIR/"
    
    # Права
    chmod 600 "$SERVICE_DIR/server.key"
    chmod 644 "$SERVICE_DIR/server.crt"
    
    echo "Серверный сертификат для $SERVICE создан!"
    echo "   Файлы: $(ls -la "$SERVICE_DIR" | grep -E 'server\.(crt|key)$' | awk '{print $5, $NF}')"
}



# 3. Функция генерации клиентского сертификата
generate_client_cert() {
    local CLIENT=$1
    local CN=$2
    
    local CLIENT_DIR="$CLIENTS_DIR/$CLIENT"
    
    if [ -f "$CLIENT_DIR/client.pfx" ] && [ -s "$CLIENT_DIR/client.pfx" ]; then
        echo "Клиентский сертификат для $CLIENT уже существует"
        return
    fi
    
    echo "Генерируем клиентский сертификат для $CLIENT..."
    mkdir -p "$CLIENT_DIR"
    
    # Конфигурация для клиентского сертификата
    cat > "$CLIENT_DIR/ext.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = Sigma
OU = Services
CN = $CN

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF
    
    # Генерируем ключ, CSR и сертификат
    openssl req -new -nodes \
        -newkey rsa:2048 \
        -keyout "$CLIENT_DIR/client.key" \
        -config "$CLIENT_DIR/ext.cnf" \
        -out "$CLIENT_DIR/client.csr"
    
    openssl x509 -req \
        -in "$CLIENT_DIR/client.csr" \
        -CA "$CA_DIR/ca.crt" \
        -CAkey "$CA_DIR/ca.key" \
        -passin pass:ca-password-change-me \
        -CAcreateserial \
        -out "$CLIENT_DIR/client.crt" \
        -days 365 \
        -sha256 \
        -extfile "$CLIENT_DIR/ext.cnf" \
        -extensions v3_req
    
    # Очистка
    rm "$CLIENT_DIR/client.csr" "$CLIENT_DIR/ext.cnf"
    
    # Копируем корневой сертификат
    cp "$CA_DIR/ca.crt" "$CLIENT_DIR/"
    
    # Создаем PFX для .NET
    openssl pkcs12 -export \
        -in "$CLIENT_DIR/client.crt" \
        -inkey "$CLIENT_DIR/client.key" \
        -out "$CLIENT_DIR/client.pfx" \
        -passout pass:
    
    chmod 600 "$CLIENT_DIR/client.key"
    chmod 644 "$CLIENT_DIR/client.pfx"
    
    echo "Клиентский сертификат для $CLIENT создан!"
    echo "   client.pfx: $(wc -c < "$CLIENT_DIR/client.pfx") байт"
}


# 4. Генерация всех сертификатов
echo ""
echo "=== Генерация серверных сертификатов ==="
generate_server_cert "postgres-user" "postgres-sigma-user"
generate_server_cert "postgres-file" "postgres-sigma-file"
generate_server_cert "postgres-chats" "postgres-sigma-chats"
generate_server_cert "postgres-auth" "postgres-sigma-users"

echo ""
echo "=== Генерация клиентских сертификатов ==="
generate_client_cert "user-service" "sigma-user-service"
generate_client_cert "file-service" "sigma-file-service"
generate_client_cert "chats-service" "sigma-chats-service"
generate_client_cert "auth-service" "sigma-auth-service"

echo ""
echo "=== Проверка сгенерированных файлов ==="
echo "Серверные сертификаты:"
find "$SERVERS_DIR" -type f -exec ls -lh {} \; 2>/dev/null || echo "  Нет файлов"
echo ""
echo "Клиентские сертификаты:"
find "$CLIENTS_DIR" -type f -exec ls -lh {} \; 2>/dev/null || echo "  Нет файлов"

echo ""
echo "Все сертификаты успешно сгенерированы!"