/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"

/**
 * Vosmenog Trust Panel — пилот (EPIC-011, TASK-1).
 * Цель пилота: проверить, что слот app_bottom рендерится
 * на живой сборке opencode (TUI).
 */

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
      <text fg={theme().text}>trust-panel pilot</text>
      <box flexGrow={1} />
      <text fg={theme().textMuted}>{props.api.app.version}</text>
    </box>
  )
}

const tui: TuiPlugin = async (api) => {
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
