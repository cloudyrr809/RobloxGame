# RobloxGame

Идея и решения по игре — в `GDD.md`. Читай перед работой над геймплеем; новые решения записывай туда.

## Как устроено

- Скрипты — только файлы в `src/`. Rojo синхронизирует их в Studio (`rojo serve` должен работать). В Studio скрипты не правь: Rojo затрёт.
  - `src/server` → ServerScriptService.Server
  - `src/client` → StarterPlayerScripts.Client
  - `src/shared` → ReplicatedStorage.Shared
- Карта и детали живут в `Place1.rbxl`, не в Rojo. Строй через Roblox Studio MCP; повторяемую геометрию — кодом. После правок карты проси меня сохранить место (Ctrl+S).
- Проверка кода: `.\tools\check.ps1` (selene + luau-lsp, строгий режим). Запускай после правок скриптов. Опечатки в именах свойств она не ловит — после запуска смотри консоль Studio.
- Инструменты лежат в `C:\Users\user\bin`.
