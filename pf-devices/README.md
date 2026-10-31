# pf-devices — the shared app platform for the tablet and the computer

`pf-tablet` and `pf-computer` are shells. Every app runs through this resource:

- **One registry (server).** A resource registers an app once with who may see it and on which
  devices. Both shells ask the server for the player's list; nothing is decided on the client.
- **One module runs everywhere.** An app is one JavaScript module (`PFApps.register(id, {mount})`)
  served from its own resource. The runtime (`html/runtime.js`) mounts it inside whichever shell is
  open. No copies per device.
- **One RPC bridge.** `ctx.rpc(method, payload)` reaches the handler the owning resource registered
  on the server, with the real player id, after the access check. Apps need no client code.
- **One push channel.** `exports['pf-devices']:Push(src, appId, event, payload)` reaches the app
  instance in the open shell; the module gets it in `ctx.on(event)` / `onEvent`.
- **Installable apps and the App Store.** `access.installable = true` makes an app appear in the
  App Store (free or paid through the bank ledger) and on the home screen once installed
  (`pf_device_apps`).
- **Sites.** `RegisterSite` publishes a website module that the Browser app renders identically on
  every device.

## Registering an app (server)

```lua
exports['pf-devices']:RegisterApp({
    id = 'taxi',                 -- letters, digits, - or _ ; unique across the server
    name = 'Taxi', icon = '🚕',
    devices = { 'tablet', 'computer' },     -- default: all devices
    entry = 'html/apps/taxi.js',            -- module script path inside THIS resource
    styles = { 'html/css/taxi.css' },       -- optional
    category = 'jobs',                      -- system | jobs | business | government | media | apps
    order = 10,                             -- sort key on the home screen
    access = { jobs = { taxi = 0 }, onduty = false },
    window = { width = 900, height = 640 }, -- optional hint for the shell
    description = 'Calls, rides and the meter',
})

exports['pf-devices']:RegisterAppHandlers('taxi', {
    getInit = function(src, payload, ctx) return { ok = true, dashboard = ... } end,
    acceptCall = function(src, payload) ... return { ok = true } end,
})
```

Legacy pages can be hosted as an iframe app: `kind = 'iframe', url = 'https://cfx-nui-<res>/page.html?device={device}'`
(`{device}` becomes `tablet` or `computer`). Push events reach an iframe as
`window.postMessage({ action = 'pfapp:event', app, event, payload })`; the event `nui` is delivered
as the bare payload, so a page that listens to its resource's `SendNUIMessage` messages works
unchanged: `exports['pf-devices']:AppEvent('trucking', 'nui', payload)` (client).

### Access rules (all listed rules must pass)

| rule | meaning |
|---|---|
| `anyone = true` | everyone |
| `jobs = { police = 0, ambulance = 2 }` or `jobs = { 'police' }` | job with at least that grade |
| `onduty = true` | the job must be on duty |
| `gov = 'fines.issue'` or `gov = { 'a', 'b' }` | pf-government `HasPermission` (any of them) |
| `admin = true` | ACE `command` / `pfdevices.admin`, or pfm-core admin/god |
| `installable = true` | shows in the App Store; usable once installed |
| `check = { resource = 'pf-x', export = 'CanUseApp' }` | `exports['pf-x']:CanUseApp(src, appId)` must return true |
| `handler = true` | the app's `__access` handler must return true |

### Handler results

A handler returns a table; `ok` defaults to `true`. Return `{ ok = false, error = 'why' }` for a
refusal. Errors thrown by a handler come back as `{ ok = false, error = 'server_error' }` and are
logged. Built-in errors: `bad_request`, `rate_limited`, `payload_too_large`, `unknown_app`,
`app_offline`, `not_authorized`, `not_installed`, `unknown_method`.

Handlers run with the player's `src` after `CanUseApp(src, appId)` passed. Everything they change
must still be checked inside the handler (distance, ownership, money through the ledger).

## Writing the module (NUI)

```js
PFApps.register('taxi', {
    async mount(container, ctx, params) {
        const { h, esc, money } = ctx;
        const res = await ctx.rpc('getInit');
        container.appendChild(h('div.pf-app', h('div.pf-app-header', h('div.pf-app-title', h('span.pf-icon', '🚕'), 'Taxi'))));
        ctx.on('callsData', (calls) => render(calls));
    },
    unmount(ctx) { /* clear timers */ },
    onEvent(event, payload, ctx) { /* or use ctx.on */ },
});
```

`ctx` gives: `app`, `device` (`tablet`/`computer`), `rpc(method, payload)`, `on/off(event, fn)`,
`notify(message, type)`, `close()`, `openApp(id, params)`, `openSite(host)`, `player()`,
`setWaypoint(x, y)`, `storage` (per-app localStorage), `el`, `h` (DOM builder), `esc`, `money`, `timeAgo`.
Base styles (`.pf-app`, `.pf-card`, `.pf-btn`, `.pf-table`, …) come from `html/runtime.css`.

## Pushing to an app (server)

```lua
exports['pf-devices']:Push(src, 'taxi', 'callsData', calls)
exports['pf-devices']:PushToJob('police', 'policemdt', 'dispatch', call, true)  -- on duty only
exports['pf-devices']:Broadcast('news', 'published', article)
exports['pf-devices']:NotifyAppsChanged(src)  -- the player's app list changed
```

Client code that already receives a server event can forward it: `exports['pf-devices']:AppEvent('taxi', 'callsData', calls)`.

## Sites

```lua
exports['pf-devices']:RegisterSite({ host = 'news.ls', name = 'Weazel News', icon = '📰',
    entry = 'html/sites/news.js', styles = { 'html/css/news.css' }, access = { anyone = true } })
exports['pf-devices']:RegisterSiteHandler('news.ls', 'latest', function(src, payload) ... end)
```
```js
PFApps.registerSite('news.ls', { mount(container, ctx) { ctx.rpc('latest') ... } });
```
`exports['pf-devices']:OpenSite('news.ls')` (client) opens the Browser app at that site.

## Shells

A shell loads `https://cfx-nui-pf-devices/html/runtime.js`, calls `PFApps.attachShell({...})`
(see the header of runtime.js), forwards `pfapp:*` NUI messages to `PFApps.handleMessage` and
calls `PFApps.refresh()` when it opens. Its client listens to `pf-devices:client:forward` and passes
the message to its NUI while open.

## Database

Migration v1 (`pf_schema_migrations`, resource `pf-devices`): `pf_device_apps(citizenid, app_id, installed_at)`.

## Tests

`[qb]/tests/specs/pfdevices_*_spec.lua` (mocked): registry and access rules, RPC routing and
limits, pushes, installs, sites, built-in apps. `tests/js/pfdevices_runtime_spec.js`: the runtime.
