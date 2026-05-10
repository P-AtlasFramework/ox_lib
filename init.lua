-- @ox_lib/init.lua — drop-in shim for ox_lib's `lib` global.
--
-- Resources that ship with ox_lib expect to do:
--     shared_script '@ox_lib/init.lua'
-- and then reference `lib.notify`, `lib.callback`, etc. We supply the
-- same surface, routing each call to atlas_core's equivalent.
--
-- This file runs as a SHARED script so it's available on both sides.
-- Per-side helpers (CreateThread, RegisterCommand, etc.) live in
-- client.lua / server.lua and overlay onto the same `lib` table.
--
-- Coverage status:
--   ✅ notify, callback, alertDialog, inputDialog, registerContext,
--      showContext, hideContext, progressBar, progressCircle,
--      requestModel, requestAnimDict, requestAnimSet, getClosestPed,
--      getClosestVehicle, getClosestPlayer, getClosestObject,
--      raycast (lib.raycast.fromCamera / cam), waitFor, addCommand
--   ⚠️  Stubs (no-op + warn): cron, dui, scaleform, marker, points,
--      logger, locale, zones, grid
--
-- Add a new wrap by appending here. The console will print
-- `[ox_lib shim] not implemented: <name>` for any caller hitting a
-- stub, so missing surface is loud rather than silent.

-- `lib` is the canonical global ox_lib consumers reference — must NOT
-- be local. lua-language-server's lowercase-global warning is wrong
-- here; suppressed deliberately.
---@diagnostic disable-next-line: lowercase-global
lib = lib or {}

local function unimplemented(name)
    -- Stub returns a function that silently swallows whatever args the
    -- caller passes (Lua discards extras automatically) and prints once.
    return function()
        print(('^3[ox_lib shim] not implemented: %s — call ignored^7'):format(name))
        return nil
    end
end

-- ── Notify ──────────────────────────────────────────────────────────
-- ox_lib's lib.notify(opts) → opts: { title, description, type, position,
-- duration, icon, iconColor, ... }
-- atlas_core's :Notify accepts the same options-table form.
-- Duplicate-set-field is the LLS recognizing the real ox_lib's signature
-- in workspace types — we're shadowing on purpose.
---@diagnostic disable-next-line: duplicate-set-field
function lib.notify(opts)
    if type(opts) ~= 'table' then opts = { description = tostring(opts) } end
    -- atlas_core Notify expects text or table; map ox shape verbatim.
    local payload = {
        text     = opts.description or opts.title or '',
        title    = opts.title,
        type     = opts.type or 'primary',
        duration = opts.duration or 5000,
        icon     = opts.icon,
        iconColor = opts.iconColor,
        position = opts.position,
    }
    if IsDuplicityVersion() then
        -- Server-side notify — atlas_core convention is a TriggerClientEvent.
        local src = opts.source
        if src then
            TriggerClientEvent('atlas_core:notify', src, payload)
        end
    else
        exports['atlas_core']:Notify(payload, payload.type, payload.duration, payload.icon)
    end
end

-- ── Asset loaders ───────────────────────────────────────────────────
if not IsDuplicityVersion() then
    function lib.requestModel(model, timeoutMs)
        return exports['atlas_core']:RequestModel(model, timeoutMs or 30000)
    end
    function lib.requestAnimDict(dict, timeoutMs)
        return exports['atlas_core']:RequestAnimDict(dict, timeoutMs or 30000)
    end
    function lib.requestAnimSet(set, timeoutMs)
        return exports['atlas_core']:RequestAnimSet(set, timeoutMs or 30000)
    end
    function lib.requestWeaponAsset(hash, timeoutMs)
        return exports['atlas_core']:RequestWeaponAsset(hash, timeoutMs or 30000)
    end
    function lib.requestScaleformMovie(name, timeoutMs)
        return exports['atlas_core']:RequestScaleformMovie(name, timeoutMs or 30000)
    end
end

-- ── Stubs (warn-on-use) ─────────────────────────────────────────────
-- These are surfaced for compatibility but call into nothing. Add an
-- implementation here when a consumer needs them.
lib.cron        = setmetatable({}, { __index = function(_, k) return unimplemented('cron.' .. k) end })
lib.logger      = unimplemented('logger')
lib.locale      = unimplemented('locale')
lib.scaleform   = setmetatable({}, { __index = function(_, k) return unimplemented('scaleform.' .. k) end })
lib.marker      = setmetatable({}, { __index = function(_, k) return unimplemented('marker.' .. k) end })
lib.points      = setmetatable({}, { __index = function(_, k) return unimplemented('points.' .. k) end })
lib.zones       = setmetatable({}, { __index = function(_, k) return unimplemented('zones.' .. k) end })
lib.grid        = setmetatable({}, { __index = function(_, k) return unimplemented('grid.' .. k) end })

-- A handful of resources rely on lib.print existing. Forward to plain
-- print so the resource doesn't crash; level prefixes get inlined.
lib.print = setmetatable({}, {
    __index = function(_, level)
        return function(...) print(('[%s]'):format(level:upper()), ...) end
    end,
})

-- waitFor — block (in a CreateThread) until cb returns non-nil or
-- timeoutMs elapses. ox_lib's exact semantics.
function lib.waitFor(cb, errMsg, timeoutMs)
    local start = GetGameTimer()
    while true do
        local result = cb()
        if result then return result end
        if timeoutMs and (GetGameTimer() - start) >= timeoutMs then
            return nil, errMsg or 'lib.waitFor timed out'
        end
        Wait(0)
    end
end
