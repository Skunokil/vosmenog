/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { createSignal, Show } from "solid-js"
import { readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"

/**
 * Vosmenog Trust Panel (EPIC-011).
 * Компактная панель внизу TUI (слот app_bottom):
 *   доверие: 1 2 3 (1=обучающий, 2=средний, 3=продвинутый)
 * Активный уровень — цветной прямоугольник (1=зелёный, 2=жёлтый, 3=красный),
 * неактивные — серые прямоугольники. Без рамок и скобок.
 * Переключение: клик по цифре, alt+1/2/3, ctrl+1/2/3 (не во всех терминалах).
 * alt+t — свернуть/развернуть.
 * detail_level из панели убран (владелец: «оставь только доверие»),
 * но ctrl+alt+1/2/3 по-прежнему переключают detail_level.
 */

const LEVELS: Array<{ n: number; name: string }> = [
  { n: 1, name: "обучающий" },
  { n: 2, name: "средний" },
  { n: 3, name: "продвинутый" },
]

const TRUST = "trust_level"
const DETAIL = "detail_level"

// ---- состояние панели (модульное: нужно и командам, и рендеру) ----
const [expanded, setExpanded] = createSignal(true)
const [trust, setTrust] = createSignal("обучающий")
const [detail, setDetail] = createSignal("обучающий")

function profilePath(api: TuiPluginApi): string {
  const config = api.state.path.config || join(process.env.HOME || "", ".config", "opencode")
  return join(config, "memory", "user-profile.md")
}

// активное значение оси: строка без "#" перед "trust_level:/detail_level:"
function readLevel(src: string, axis: "trust_level" | "detail_level", fallback: string): string {
  const re = new RegExp(`^\\s*${axis}:\\s*(\\S+)`, "m")
  const m = src.match(re)
  return m ? m[1] : fallback
}

function loadProfile(api: TuiPluginApi) {
  try {
    const src = readFileSync(profilePath(api), "utf8")
    setTrust(readLevel(src, TRUST, "обучающий"))
    // деградация: нет detail_level -> берётся trust_level
    setDetail(readLevel(src, DETAIL, trust()))
  } catch {
    // файл недоступен — оставляем деградацию (обучающий)
  }
}

// переписать yaml-блок: активную ось раскомментировать, остальные закомментировать
function writeLevel(api: TuiPluginApi, axis: "trust_level" | "detail_level", level: string): boolean {
  const file = profilePath(api)
  try {
    const src = readFileSync(file, "utf8")
    const fence = /```yaml([\s\S]*?)```/
    const m = src.match(fence)
    if (!m) return false
    const next = m[1].replace(
      /^(\s*)#?\s*(trust_level|detail_level):\s*(\S+)(\s*#.*)?$/gm,
      (_, ind, key, val, comment) => {
        const active = key === axis && val === level
        return active ? `${ind}${key}: ${val}${comment ?? ""}` : `${ind}# ${key}: ${val}${comment ?? ""}`
      },
    )
    writeFileSync(file, src.replace(fence, "```yaml" + next + "```"))
    return true
  } catch {
    return false
  }
}

function selectTrust(api: TuiPluginApi, level: string) {
  const prev = trust()
  setTrust(level)
  if (!writeLevel(api, TRUST, level)) setTrust(prev)
}

function selectDetail(api: TuiPluginApi, level: string) {
  const prev = detail()
  setDetail(level)
  if (!writeLevel(api, DETAIL, level)) setDetail(prev)
}

// цвет уровня: 1=зелёный (обучающий), 2=жёлтый (средний), 3=красный (продвинутый)
function levelColor(api: TuiPluginApi, name: string) {
  const theme = api.theme.current
  switch (name) {
    case "обучающий":
      return theme.success
    case "средний":
      return theme.warning
    case "продвинутый":
      return theme.error
    default:
      return theme.textMuted
  }
}

function LevelButton(props: {
  api: TuiPluginApi
  label: string
  color: object
  active: boolean
  onClick: () => void
}) {
  const theme = () => props.api.theme.current
  return (
    <text bg={props.active ? props.color : theme().border} fg={theme().background} onMouseDown={props.onClick}>
      {props.label}
    </text>
  )
}

function Expanded(props: { api: TuiPluginApi }) {
  const theme = () => props.api.theme.current
  return (
    <box flexDirection="row" gap={1}>
      <text fg={theme().text}>доверие:</text>
      {LEVELS.map((l) => (
        <LevelButton
          api={props.api}
          label={`${l.n}`}
          color={levelColor(props.api, l.name)}
          active={trust() === l.name}
          onClick={() => selectTrust(props.api, l.name)}
        />
      ))}
      <text fg={theme().textMuted}>alt+1-3 · alt+t ↑/↓</text>
    </box>
  )
}

function View(props: { api: TuiPluginApi }) {
  const theme = () => props.api.theme.current
  return (
    <box
      width="100%"
      flexDirection="row"
      gap={1}
      paddingLeft={2}
      paddingRight={2}
      paddingBottom={1}
      paddingTop={1}
    >
      <text fg={theme().textMuted}>[vosmenog]</text>
      <Show
        when={expanded()}
        fallback={
          <text fg={theme().text}>
            доверие: {trust()} <span fg={theme().textMuted}>(alt+t развернуть)</span>
          </text>
        }
      >
        <Expanded api={props.api} />
      </Show>
      <box flexGrow={1} />
      <text fg={theme().textMuted}>{props.api.app.version}</text>
    </box>
  )
}

const tui: TuiPlugin = async (api) => {
  loadProfile(api)

  const set = (axis: "trust_level" | "detail_level", level: string) => () => {
    if (axis === TRUST) selectTrust(api, level)
    else selectDetail(api, level)
  }

  const trustCmds = LEVELS.map((l, i) => ({
    name: `vosmenog.trust.${i}`,
    title: `trust: ${l.n} (${l.name})`,
    run: set(TRUST, l.name),
  }))
  const detailCmds = LEVELS.map((l, i) => ({
    name: `vosmenog.detail.${i}`,
    title: `detail: ${l.n} (${l.name})`,
    run: set(DETAIL, l.name),
  }))

  api.keymap.registerLayer({
    commands: [
      ...trustCmds,
      ...detailCmds,
      { name: "vosmenog.toggle", title: "trust-panel: свернуть/развернуть", run: () => setExpanded(!expanded()) },
    ],
    bindings: [
      // ctrl+цифры не работают в большинстве терминалов (ctrl+2 = NUL) — поэтому alt+цифры
      { key: "ctrl+1,alt+1", cmd: "vosmenog.trust.0", desc: "trust: 1 (обучающий)" },
      { key: "ctrl+2,alt+2", cmd: "vosmenog.trust.1", desc: "trust: 2 (средний)" },
      { key: "ctrl+3,alt+3", cmd: "vosmenog.trust.2", desc: "trust: 3 (продвинутый)" },
      // detail скрыт из панели, но клавиши живы
      { key: "ctrl+alt+1", cmd: "vosmenog.detail.0", desc: "detail: 1 (обучающий)" },
      { key: "ctrl+alt+2", cmd: "vosmenog.detail.1", desc: "detail: 2 (средний)" },
      { key: "ctrl+alt+3", cmd: "vosmenog.detail.2", desc: "detail: 3 (продвинутый)" },
      // ctrl+t занят системой (variant_cycle) — используем alt+t
      { key: "alt+t", cmd: "vosmenog.toggle", desc: "trust-panel: свернуть/развернуть" },
    ],
  })

  api.slots.register({
    order: 100,
    slots: {
      app_bottom() {
        return <View api={api} />
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id: "vosmenog.trust-panel",
  tui,
}

export default plugin
