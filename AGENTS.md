# AGENTS.md — Vosmenog

> Проект совершенствования ролевой модели Воси.
> Это НЕ продукт — это мета-проект: инструкции, метод, память.

---

## Что здесь

| Что | Где |
|-----|-----|
| Репозиторий | `~/projects/vosmenog/` (клон `git@github.com:Skunokil/vosmenog.git`) |
| Планирование | `~/projects/team-work/vosmenog/` |
| Установленный фреймворк | `~/agent-os/` |
| Память сессий | `~/projects/team-work/vosmenog/sessions/` |

---

## Git

```bash
git remote -v  # origin git@github.com:Skunokil/vosmenog.git
git branch     # main (единственная ветка)
```

- Ветка: `main` (одна, проект методологический)
- **Коммитит Вося** (после визуального подтверждения Эпира), **пушит Эпир**
- SSH: `git@github.com:Skunokil/vosmenog.git`

**Push-команды для Эпира (выдаю при resolve):**
```bash
cd ~/projects/vosmenog
git add -A
git commit -m '<описание>'
git push origin main
```
После коммита я выдаю набор команд — Эпир копирует и выполняет.

---

## Команды

Проект методологический — сборки/деплоя нет.

```bash
# Статус репозитория
git -C ~/projects/vosmenog status
git -C ~/projects/vosmenog log --oneline -10

# Планирование
ls ~/projects/team-work/vosmenog/epics/
ls ~/projects/team-work/vosmenog/backlog/
```

---

## Гейты — что требует go

| Действие | Кто решает |
|----------|-----------|
| Правка METHOD.md | Только Эпир |
| Правка AGENTS.md | Только Эпир |
| Правка шаблонов EPIC/TASK/BUG | Только Эпир |
| Правка opencode.json | Только Эпир |
| Правка STARTUP.md | Только Эпир |
| Изменение в ~/agent-os/ | Только Эпир |
| Изменение в ~/.bashrc | Только Эпир |
| Push на GitHub | Только Эпир (после коммита Восей) |
| Чтение любых файлов | Вося (без gate) |
| Создание/обновление EPIC в team-work | Вося (после go) |
| Создание TASK/BUG | Вося (в рамках эпика) |
| Resolve эпика | Вося (с ретроспективой) |

---

## Структура проекта

```
~/projects/vosmenog/
  METHOD.md           # Ядро метода (контракт исполнителя)
  AGENTS.md           # Этот файл — проектные слоты
  EPIC.template.md    # Шаблон эпика
  TASK.template.md    # Шаблон задачи
  BUG.template.md     # Шаблон бага
  GUIDE.md            # Руководство по установке
  setup.sh            # Скрипт установки
  update.sh           # Скрипт обновления
  persona_vosya.md    # Персона Воси
  payload/            # Установочные файлы

~/projects/team-work/vosmenog/
  epics/              # Активные EPIC-документы
  sessions/           # journal.md + archive/
  archive/            # Закрытые эпики, рекон-отчёты
  backlog/            # ROADMAP, vision, черновики
  bugs/               # BUG-файлы
  exchange/           # incoming/outgoing/archive — обмен с Минотавром
```

---

## Правила для работы в проекте

1. Вося не редактирует METHOD.md и шаблоны — это зона Эпира.
2. Вося ведёт team-work/vosmenog/ — EPIC, backlog, sessions, bugs.
3. Изменения в ~/.config/opencode/ — только через Эпира.
4. `go vos` переключает в этот проект (см. CLAUDE.md сервера).
5. Каждая сессия завершается рефлексией в sessions/.

### Границы репозитория

- **В репозиторий** — только обезличенный метод работы: METHOD.md, шаблоны,
  AGENTS.md, setup/update скрипты. Никаких серверных конфигов, секретов,
  специфики проектов Эпира.
- **Вне репозитория** — CLAUDE.md, .bashrc, opencode.json, STARTUP.md,
  team-work/ документы. Они живут на сервере, правятся отдельно.
- **Общие практики** — выносятся в репозиторий (METHOD.md).
- **Локальные процедуры** — остаются в team-work/ и серверных конфигах.
