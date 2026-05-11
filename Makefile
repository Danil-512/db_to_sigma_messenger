# Makefile в корне проекта
.PHONY: certs clean-certs setup-dirs copy-certs help

help:
	@echo "Доступные команды:"
	@echo "  make certs      - Сгенерировать все сертификаты"
	@echo "  make setup-dirs - Создать структуру и скопировать сертификаты в postgres-custom"
	@echo "  make clean-certs - Удалить все сертификаты"
	@echo "  make all        - Полная инициализация"

certs:
	@echo "Генерация сертификатов..."
	cd scripts && bash generate-certs.sh
	@echo "Сертификаты сгенерированы"

setup-dirs:
	@echo "Копирование сертификатов в postgres-custom..."
	@for service in user file chats auth; do \
		echo "  Обработка $$service..."; \
		cp certs/servers/postgres-$$service/server.crt postgres-custom/$$service/ 2>/dev/null || echo "    server.crt не найден для $$service"; \
		cp certs/servers/postgres-$$service/server.key postgres-custom/$$service/ 2>/dev/null || echo "    server.key не найден для $$service"; \
		cp certs/servers/postgres-$$service/ca.crt postgres-custom/$$service/ 2>/dev/null || echo "    ca.crt не найден для $$service"; \
	done
	@echo "Сертификаты скопированы"

clean-certs:
	@echo "Удаление сертификатов..."
	rm -rf certs/ca/*
	rm -rf certs/servers/*
	rm -rf certs/clients/*
	@for service in user file chats auth; do \
		rm -f postgres-custom/$$service/server.crt; \
		rm -f postgres-custom/$$service/server.key; \
		rm -f postgres-custom/$$service/ca.crt; \
	done
	@echo "Сертификаты удалены"

all: certs setup-dirs
	@echo "Полная инициализация завершена!"