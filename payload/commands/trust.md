---
description: Сменить уровень доверия (trust_level) — обучающий / средний / продвинутый
---

Владелец вызвал `/trust $ARGUMENTS`. Смени уровень доверия на «$ARGUMENTS»:

1. Проверь, что значение — одно из: `обучающий`, `средний`, `продвинутый`. Если нет —
   сообщи и не меняй ничего.
2. Обнови `trust_level` в `~/.config/opencode/memory/user-profile.md` (единый источник
   истины для Восьменога и Минотавра): раскомментируй нужную строку, остальные
   закомментируй. Файл содержит кириллицу — используй python3, НЕ sed.
3. Обнови секцию «## Уровень доверия» в `~/.claude/CLAUDE.md`: строку «Текущий:»
   (новый уровень и дату смены). Не переписывай остальной роутер.
4. Кратко подтверди владельцу: было → стало.

Пример переключения уровня в user-profile.md (python3, безопасно для кириллицы):

```bash
python3 - "обучающий" << 'PYEOF'
import sys, re
level = sys.argv[1]
path = "/home/skunokil/.config/opencode/memory/user-profile.md"
src = open(path).read()
def swap(m):
    body = m.group(1)
    out = re.sub(
        r"^(\s*)#?\s*(trust_level):\s*(\S+)(\s*#.*)?$",
        lambda mm: (
            f"{mm.group(1)}{mm.group(2)}: {mm.group(3)}{mm.group(4) or ''}"
            if mm.group(2) == "trust_level" and mm.group(3) == level
            else f"{mm.group(1)}# {mm.group(2)}: {mm.group(3)}{mm.group(4) or ''}"
        ),
        body, flags=re.M)
    return "```yaml" + out + "```"
src2 = re.sub(r"```yaml([\s\S]*?)```", swap, src)
if src2 != src:
    open(path, "w").write(src2)
    print("trust_level ->", level)
else:
    print("не изменилось (значение уже активное?)")
PYEOF
```
