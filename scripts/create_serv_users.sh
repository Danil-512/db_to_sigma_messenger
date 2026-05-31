#!/bin/bash
# scripts/init-app-user.sh
# Создание пользователя с минимальными правами (только DML) для работы с сервисами бэкенда
# Выполняется при первой инициализации PostgreSQL

set -e
#
echo "------ Создание прикладного пользователя для бэкенда ------"
#
# Ожидание готовности PostgreSQL
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" 2>/dev/null; do
    echo "Ожидание готовности PostgreSQL..."
    sleep 2
done
#
# Проверка, что переменные окружения заданы
if [ -z "$APP_DB_USER" ] || [ -z "$APP_DB_PASSWORD" ]; then
    echo "ОШИБКА: APP_DB_USER или APP_DB_PASSWORD не заданы!"
    exit 1
fi
#
echo "PostgreSQL готов. Создание пользователя $APP_DB_USER..."
#
# Создаем пользователя и выдаем права
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- =============================================
    -- 1. Создание роли для входа
    -- =============================================
    DO \$\$
    BEGIN
        IF NOT EXISTS (
            SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_DB_USER}'
        ) THEN
            CREATE ROLE ${APP_DB_USER} WITH
                LOGIN
                PASSWORD '${APP_DB_PASSWORD}'
                NOSUPERUSER
                NOCREATEDB
                NOCREATEROLE
                NOINHERIT
                NOREPLICATION
                CONNECTION LIMIT 50;
            RAISE NOTICE 'Роль % создана', '${APP_DB_USER}';
        ELSE
            RAISE NOTICE 'Роль % уже существует', '${APP_DB_USER}';
        END IF;
    END
    \$\$;

    -- =============================================
    -- 2. Базовые права на подключение и схему
    -- =============================================
    GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${APP_DB_USER};
    GRANT USAGE ON SCHEMA public TO ${APP_DB_USER};

    -- =============================================
    -- 3. Права на существующие таблицы
    -- =============================================
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${APP_DB_USER};

    -- =============================================
    -- 4. Права на последовательности (для serial/bigserial)
    -- =============================================
    GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${APP_DB_USER};

    -- =============================================
    -- 5. Права по умолчанию (для таблиц, созданных в будущем)
    -- =============================================
    ALTER DEFAULT PRIVILEGES FOR ROLE ${POSTGRES_USER} IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_DB_USER};

    ALTER DEFAULT PRIVILEGES FOR ROLE ${POSTGRES_USER} IN SCHEMA public
        GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${APP_DB_USER};

    -- =============================================
    -- 6. Запрещаем лишнее (дополнительная безопасность)
    -- =============================================
    REVOKE CREATE ON SCHEMA public FROM ${APP_DB_USER};
    REVOKE ALL ON DATABASE ${POSTGRES_DB} FROM PUBLIC;
EOSQL

echo "Пользователь $APP_DB_USER создан с правами только на DML (SELECT, INSERT, UPDATE, DELETE)"
