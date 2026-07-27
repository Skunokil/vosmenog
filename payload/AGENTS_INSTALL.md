# AGENTS_INSTALL.md — Установка новых агентов в Vosmenog

> Как добавить нового агента (Зину, Минотавра или любого другого) в фреймворк.

---

## 1. Где живут агенты

| Тип | Где | Формат |
|-----|-----|--------|
| **Режимы opencode** | `~/.config/opencode/agents/` | YAML frontmatter + MD-тело |
| **Головы (облачные)** | `~/agent-os/payload/shared/skills/` или Claude Projects | session_start.md + persona + workflow |
| **Скиллы** | `~/.config/opencode/skills/` | YAML frontmatter + MD-тело |

**Режим opencode** — агент работает на сервере (через opencode), с правами из frontmatter.
**Голова** — агент работает в облачном Claude/ChatGPT, без доступа к серверу.

---

## 2. Установка режима opencode (как Вося)

### Шаг 1: Создай файл агента

`~/.config/opencode/agents/<Name>.md`:

```markdown
---
description: >-
  Краткое описание: кто это, чем занимается, когда переключаться.
mode: all
temperature: 0.1
tools:
  read: true
  grep: true
  glob: true
  bash: true
  edit: true
  write: true
  todowrite: true
  skill: true
  webfetch: false
  task: false
permission:
  bash:
    "*": ask
    "ls*": allow
    "cat *": allow
    "grep *": allow
    "git status*": allow
    "git push*": deny
    "rm -rf*": deny
    "sudo*": deny
  edit:
    "*": ask
  external_directory:
    "*": allow
    "~/projects/team-work/**": allow
---

# Я — <Имя>

<Тело агента: кто я, как работаю, правила, стопы.>
```

### Шаг 2: Подключи в opencode.json

`~/.config/opencode/opencode.json`:

```json
{
  "default_agent": "Vosmenog",
  "instructions": [
    "~/.config/opencode/memory/STARTUP.md",
    "~/agent-os/METHOD.md"
  ]
}
```

Агент автоматически появится в списке (Tab для переключения).

### Шаг 3: Проверь

```
opencode agent list
```

Новый агент должен быть в списке с пометкой режима.

---

## 3. Установка головы (облачный агент, как Минотавр)

### Шаг 1: Создай проектное пространство

- Claude Projects (claude.ai) → «Create Project»
- ChatGPT → «Custom GPT» или проект
- Cursor → Rules

### Шаг 2: Загрузи файлы

Из `~/agent-os/payload/shared/skills/` или создай свои:
- `session_start.md` — роутинг (обязательно)
- `persona_<name>.md` — персона и характер
- `<name>-workflow.md` — воркфлоу взаимодействия
- `dev-rules.md` — правила разработки (опционально)

### Шаг 3: Настрой системный промт

Первое сообщение в проекте:
```
Ты — <Имя>. Читай session_start.md.
```

---

## 4. Установка скилла

### Шаг 1: Создай файл скилла

`~/.config/opencode/skills/<name>/SKILL.md`:

```markdown
---
name: <name>
description: >-
  Когда грузить этот скилл: <описание триггера>.
compatibility: opencode
---

# <Название скилла>

<Инструкции: что делает, когда применять, примеры.>
```

### Шаг 2: Подключи

Скилл подключается через `skill` tool в opencode. Агент грузит его по запросу
или по триггеру из `description`.

---

## 5. Правила

- **Каждый агент — изолирован.** Не дублируй правила METHOD.md в новых агентах —
  они грузят METHOD.md через instructions.
- **Permissions — строже, чем у Вося.** Вося — пример минимальных прав. Новые агенты
  могут быть шире (write, bash) или уже (только read).
- **Не трогай чужие агенты.** Редактирование agents/ — только владелец.
- **Скиллы — переиспользуемы.** Один скилл может работать у нескольких агентов.

---

## Пример: Зина (писатель)

Зина — агент-писатель дляkontenta. Установка:

1. **Режим opencode** (если нужен доступ к серверу):
   - Файл: `~/.config/opencode/agents/Zina.md`
   - Permissions: read + write (для контента), bash: ограниченный
   - Скиллы: `tutor` (обучение), собственные скиллы письма

2. **Голова** (если нужен только облачный анализ):
   - Claude Projects: загрузить `persona_zina.md`, `session_start.md`
   - Системный промт: «Ты — Зина, писатель. Читай session_start.md.»

3. **Скиллы** (для специализации):
   - `skills/writing/SKILL.md` — правила стиля, форматирования
   - `skills/editing/SKILL.md` — проверка и редактура

---

> Вопросы? Спрашивай — помогу разобраться с конкретным агентом.
