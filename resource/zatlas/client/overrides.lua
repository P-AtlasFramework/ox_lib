--[[
    Atlas → ox_lib override layer.

    Re-routes ox_lib's `lib.*` UI surfaces through atlas_core's
    exports so resources written against ox_lib render in Atlas's
    own UI (one notification system, one progress bar, etc.) instead
    of ox_lib's bundled NUI.

    HOW THIS WORKS
    --------------
    ox_lib's fxmanifest globs `resource/**/client/*.lua` alphabetically.
    The standard UI surfaces live at `resource/interface/client/*.lua`
    (notify, progress, alert, input, context, textui, menu). This file
    lives at `resource/zatlas/client/overrides.lua` so the `z`-prefixed
    directory sorts AFTER `interface/` and our re-defines win.

    Each `function lib.X(...) end` triggers ox_lib's `__newindex`
    metatable in `resource/init.lua`:
        __newindex = function(self, key, fn)
            rawset(self, key, fn)
            if debug_getinfo(2, 'S').short_src:find('@ox_lib/resource') then
                exports(key, fn)
            end
        end
    The path check passes (we're under `@ox_lib/resource/`), so the
    export is REPLACED with our function. Consumer resources hitting
    `lib.notify(data)` from their own `@ox_lib/init.lua` shared_script
    route through `exports.ox_lib.notify(nil, data)` → our function.

    CALLERS REACH US TWO WAYS
    -------------------------
    1. Internal: ox_lib's own RegisterNetEvent('ox_lib:notify', lib.notify)
       calls `lib.notify(data)` — single arg.
    2. External: consumer resources via @ox_lib/init.lua route through
       `export.ox_lib.notify(nil, data)` — first arg nil, data second.
       (Some callers use the colon form `exports.ox_lib:notify(data)`
       which passes the exports table as self.)

    To handle both, every override accepts `(a, b)` and picks data as
    `b` when present, else `a`. Same pattern across all surfaces.

    MAINTENANCE
    -----------
    This file ships as part of Atlas's ox_lib install. If you update
    ox_lib from the upstream release zip, the `resource/zatlas/`
    directory is OUR addition — preserve it across updates.
]]

local function pickData(a, b)
    return b ~= nil and b or a
end

-- ── Notify ──────────────────────────────────────────────────────────
-- ox_lib NotifyProps: { id, title, description, duration, position,
-- type, style, icon, iconAnimation, iconColor, alignIcon, sound }
-- atlas_core Notify accepts a table with title/description/type/duration/
-- icon and forwards to the Atlas NUI notification surface.
---@diagnostic disable-next-line: duplicate-set-field
function lib.notify(a, b)
    local data = pickData(a, b)
    if type(data) ~= 'table' then return end
    -- atlas_core's Notify reads .description first then .message/.text;
    -- map ox_lib's shape across cleanly. iconAnimation + iconColor pass
    -- through as-is since atlas_core accepts them.
    exports['atlas_core']:Notify(data, data.type, data.duration, data.icon)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.defaultNotify(a, b)
    local data = pickData(a, b)
    if type(data) ~= 'table' then return end
    data.type = data.status or data.type
    if data.type == 'inform' then data.type = 'info' end
    return lib.notify(data)
end

-- ── Progress ────────────────────────────────────────────────────────
-- ox_lib ProgressProps: { label, duration, useWhileDead, allowRagdoll,
-- allowCuffed, allowFalling, canCancel, anim, prop, disable }.
-- atlas_core Progressbar accepts an opts table with the same shape
-- (it was modelled on ox_lib's Lation-style API), returns bool.
---@diagnostic disable-next-line: duplicate-set-field
function lib.progressBar(a, b)
    local data = pickData(a, b)
    if type(data) ~= 'table' then return false end
    return exports['atlas_core']:Progressbar(data)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.progressCircle(a, b)
    local data = pickData(a, b)
    if type(data) ~= 'table' then return false end
    return exports['atlas_core']:CircleProgressBar(data)
end

function lib.cancelProgress()
    exports['atlas_core']:cancelProgress()
end

function lib.progressActive()
    -- atlas_core exports `progressActive` (linear) and `circleProgressActive`
    -- (circular) separately. Either active = "a progress bar is showing".
    local linear  = exports['atlas_core']:progressActive()
    local circle  = exports['atlas_core']:circleProgressActive()
    return linear or circle or false
end

-- ── Alert dialog ────────────────────────────────────────────────────
-- ox_lib alertDialog(data, timeout) returns 'confirm' or 'cancel'.
-- atlas_core AlertDialog(opts) takes header/content/labels and returns
-- the same string verdict (per feedback_atlas_core_dialog_api memo).
---@diagnostic disable-next-line: duplicate-set-field
function lib.alertDialog(a, b, c)
    local data = pickData(a, b)
    local timeout = (b ~= nil and b ~= data) and b or c   -- 3rd-arg form via export
    if type(data) ~= 'table' then return 'cancel' end
    -- Map ox_lib field names → atlas_core field names. ox_lib uses
    -- `header` + `content` + `labels`; atlas_core uses the same exact
    -- naming, so this is mostly a passthrough.
    local opts = {
        header   = data.header,
        content  = data.content,
        centered = data.centered,
        cancel   = data.cancel ~= false,
        labels   = data.labels,
        size     = data.size,
        timeout  = data.timeout or timeout,
    }
    return exports['atlas_core']:AlertDialog(opts)
end

function lib.closeAlertDialog()
    -- No direct atlas_core export; surface a no-op + warn. The user's
    -- existing alert closes on confirm/cancel anyway, this only matters
    -- if a programmatic close is needed.
    print('^3[atlas/ox_lib overrides] closeAlertDialog called — atlas_core has no programmatic close hook yet^7')
end

-- ── Input dialog ────────────────────────────────────────────────────
-- ox_lib inputDialog(heading, rows, options) → table of values
-- atlas_core InputDialog(heading, rows, options) → same shape (per the
-- feedback_atlas_core_dialog_api memo). Note: atlas_core uses
-- type='input' (not 'text'), isRequired (not 'required') — ox_lib
-- callers using the modern shape work directly. Older `type='text'`
-- rows get re-mapped here.
---@diagnostic disable-next-line: duplicate-set-field
function lib.inputDialog(a, b, c, d)
    -- (heading, rows, options) direct call OR
    -- (nil/self, heading, rows, options) via export.
    local heading, rows, options
    if type(a) == 'string' then
        heading, rows, options = a, b, c
    else
        heading, rows, options = b, c, d
    end
    if type(rows) ~= 'table' then return nil end
    -- Remap any ox_lib row that uses type='text' (legacy/v3) → 'input'
    -- so atlas_core's input handler matches. Mutates in-place; that's
    -- fine since the caller owns the table for the duration of the call.
    for _, row in ipairs(rows) do
        if row.type == 'text' then row.type = 'input' end
        if row.required ~= nil and row.isRequired == nil then
            row.isRequired = row.required
        end
    end
    return exports['atlas_core']:InputDialog(heading, rows, options)
end

function lib.closeInputDialog()
    print('^3[atlas/ox_lib overrides] closeInputDialog called — atlas_core has no programmatic close hook yet^7')
end

-- ── Context menu ────────────────────────────────────────────────────
-- ox_lib registers contexts by id then shows by id. atlas_core's API
-- is identical: RegisterContext({id, title, options}) + ShowContext(id).
---@diagnostic disable-next-line: duplicate-set-field
function lib.registerContext(a, b)
    local context = pickData(a, b)
    if type(context) ~= 'table' then return end
    exports['atlas_core']:RegisterContext(context)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.showContext(a, b)
    local id = pickData(a, b)
    if type(id) ~= 'string' then return end
    exports['atlas_core']:ShowContext(id)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.hideContext(_a, _b)
    -- ox_lib's hideContext takes (onExit) optional boolean — we
    -- ignore it; atlas_core's HideContext doesn't differentiate.
    exports['atlas_core']:HideContext()
end

function lib.getOpenContextMenu()
    local ok, id = pcall(function() return exports['atlas_core']:GetOpenContextMenu() end)
    return ok and id or nil
end

-- ── TextUI ──────────────────────────────────────────────────────────
-- ox_lib showTextUI(text, options) — text is a string, options is a
-- table. atlas_core TextUI(data) takes a single table { text, key, ... }.
---@diagnostic disable-next-line: duplicate-set-field
function lib.showTextUI(a, b, c)
    local text, options
    if type(a) == 'string' then
        text, options = a, b
    else
        text, options = b, c
    end
    if type(text) ~= 'string' then return end
    local data = options or {}
    data.text = text
    exports['atlas_core']:TextUI(data)
end

function lib.hideTextUI()
    exports['atlas_core']:HideTextUI()
end

function lib.isTextUIOpen()
    -- atlas_core's facade doesn't track open state today. Default false
    -- — consumers using this for gating logic get the same effect as
    -- "no TextUI shown right now". Wire properly when atlas_core grows
    -- a native TextUI implementation.
    return false
end

-- ── Note ────────────────────────────────────────────────────────────
-- menu (lib.registerMenu / showMenu / hideMenu / setMenuOptions) is
-- INTENTIONALLY not overridden. atlas_core's menu surface has a
-- different shape than ox_lib's interactive menu, and the use cases
-- differ enough that mapping would surprise consumers. ox_lib's menu
-- continues to render via its own NUI. If a consumer needs a single
-- menu system, they should use lib.registerContext (which IS routed)
-- or atlas_core's RegisterContext directly.

print('^2[atlas/ox_lib overrides] lib.notify / progressBar / progressCircle / alertDialog / inputDialog / registerContext / showContext / hideContext / TextUI routed through atlas_core^7')
