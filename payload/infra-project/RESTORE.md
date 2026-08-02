# Восстановление из бэкапа (RESTORE)

Бэкап: restic → S3 (`RESTIC_REPOSITORY` из `~/projects/infra/.env`).
Тег `db` — дампы PostgreSQL, тег `files` — файлы/конфиги/секреты.

## Перед восстановлением

1. Пароль restic (`RESTIC_PASSWORD`) — у владельца в менеджере паролей. Без него
   данные не восстановить.
2. Креды S3 — в `~/projects/infra/.env` (на новой машине его надо создать заново).
3. Команды ниже выполняются с сервера, где живёт проект `~/projects/infra`.

## Список снапшотов

```bash
cd ~/projects/infra && ./restore.sh list
```

## Восстановить дампы БД (безопасно)

```bash
./restore.sh db            # последний дамп
./restore.sh db <SNAP_ID>  # конкретный снапшот
```

Дампы появятся в `~/projects/infra/restore-out/tmp/restic-db.*/*.sql.gz`.
Залить вручную (пример):

```bash
gunzip -c restore-out/tmp/restic-db.*/<контейнер>_<база>.sql.gz | docker exec -i <контейнер> psql -U <пользователь> -d <база>
```

## Залить дампы автоматически (ДЕСТРУКТИВНО — перезаписывает текущие БД)

```bash
./restore.sh db-apply            # последний дамп
./restore.sh db-apply <SNAP_ID>
```

Скрипт спросит подтверждение, затем перезальёт базы из списка `CONTAINERS` (в
`restore.sh` / `backup-db.sh`).

## Восстановить файлы

```bash
./restore.sh files --target /path/to/restore
./restore.sh files <SNAP_ID> --target /path/to/restore
```

Файлы восстановятся в `/path/to/restore` с сохранением структуры:
`/etc`, `/home/<user>/projects`, `/home/<user>/.ssh` и т.д.
Скопируй нужное в боевые места вручную.

## Порядок при полной потере сервера

1. Поднять новый сервер, установить docker, restic.
2. Склонировать `~/projects/infra` (репозиторий) и восстановить `.env` (креды S3 + пароль restic).
3. `restic init` — если репозиторий уже существует, init вернёт ошибку «already exists» — это нормально.
4. `./restore.sh list` — убедиться, что репозиторий доступен.
5. `./restore.sh db` → залить дампы (`db-apply`).
6. `./restore.sh files --target /` → скопировать проекты, конфиги, ssh-ключи.
7. Поднять стеки (docker compose up в проектах).

## Проверка бэкапа

```bash
restic snapshots   # после source .env
tail -20 ~/projects/infra/backup.log
```
