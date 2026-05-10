-- ox_lib client overlay — UI shims + closest/raycast helpers.
--
-- `lib` is already provided by init.lua (shared). Here we attach the
-- functions that are client-only.

-- ── Progress UI ─────────────────────────────────────────────────────
-- ox: lib.progressBar(opts) and lib.progressCircle(opts).
-- atlas_core: exports['atlas_core']:Progressbar(opts) / :CircleProgressBar(opts).
-- Same options bag (label, duration, anim, prop, disable, canCancel, icon).
-- Both honor the single-active gate added in atlas_core v post-2026-05-10.
---@diagnostic disable-next-line: duplicate-set-field
function lib.progressBar(opts)
    return exports['atlas_core']:Progressbar(opts)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.progressCircle(opts)
    return exports['atlas_core']:CircleProgressBar(opts)
end

function lib.cancelProgress()
    return exports['atlas_core']:cancelProgress()
end

function lib.progressActive()
    return exports['atlas_core']:progressActive()
end

-- ── Dialogs ─────────────────────────────────────────────────────────
-- ox: lib.alertDialog(opts) → returns 'confirm' | 'cancel'.
-- ox: lib.inputDialog(heading, rows, opts) → returns array of values.
---@diagnostic disable-next-line: duplicate-set-field
function lib.alertDialog(opts)
    return exports['atlas_core']:AlertDialog(opts)
end

---@diagnostic disable-next-line: duplicate-set-field
function lib.inputDialog(heading, rows, opts)
    return exports['atlas_core']:InputDialog(heading, rows, opts)
end

-- ── Context menus ───────────────────────────────────────────────────
-- ox: lib.registerContext(opts), lib.showContext(id), lib.hideContext().
---@diagnostic disable-next-line: duplicate-set-field
function lib.registerContext(opts)
    return exports['atlas_core']:RegisterContext(opts)
end
---@diagnostic disable-next-line: duplicate-set-field
function lib.showContext(id)
    return exports['atlas_core']:ShowContext(id)
end
---@diagnostic disable-next-line: duplicate-set-field
function lib.hideContext()
    return exports['atlas_core']:HideContext()
end
function lib.getOpenContextMenu()
    return exports['atlas_core']:GetOpenContextMenu()
end

-- ── Callbacks ───────────────────────────────────────────────────────
-- ox: lib.callback(name, sourceOrTimeout, cb, ...) — blocking + non-blocking.
-- atlas_core: TriggerServerCallback(name, cb, ...).
-- We approximate: if `cb` is a function, fire non-blocking; otherwise
-- block via promise (matching ox_lib's await-style).
lib.callback = setmetatable({}, {
    __call = function(_, name, _timeoutOrSource, cb, ...)
        local args = { ... }
        if type(cb) == 'function' then
            exports['atlas_core']:TriggerServerCallback(name, cb, table.unpack(args))
        else
            -- Blocking form: ox_lib returns the callback result directly.
            local p = promise.new()
            exports['atlas_core']:TriggerServerCallback(name, function(...) p:resolve({ ... }) end, table.unpack(args))
            local r = Citizen.Await(p)
            return table.unpack(r or {})
        end
    end,
})

-- ox: lib.callback.register('name', fn) — client-side callback receiver.
---@diagnostic disable-next-line: duplicate-set-field
function lib.callback.register(name, fn)
    return exports['atlas_core']:CreateClientCallback(name, fn)
end

-- ── Closest entity ──────────────────────────────────────────────────
-- ox: lib.getClosestPlayer(coords, maxDistance, includeOwn)
--     returns id, ped, coords
function lib.getClosestPlayer(coords, _maxDistance, _includeOwn)
    return exports['atlas_core']:GetClosestPlayer(coords or GetEntityCoords(PlayerPedId()))
end

-- ox: lib.getClosestVehicle / Ped / Object — these aren't 1:1 exposed by
-- atlas_core; using game pool natives directly inline.
local function closestFromPool(pool, coords, maxDistance)
    local nearest, nearestDist
    for _, ent in ipairs(GetGamePool(pool)) do
        local d = #(GetEntityCoords(ent) - coords)
        if (not maxDistance or d <= maxDistance) and (not nearestDist or d < nearestDist) then
            nearest, nearestDist = ent, d
        end
    end
    return nearest, nearestDist
end

function lib.getClosestVehicle(coords, maxDistance)
    return closestFromPool('CVehicle', coords or GetEntityCoords(PlayerPedId()), maxDistance)
end

function lib.getClosestPed(coords, maxDistance)
    return closestFromPool('CPed', coords or GetEntityCoords(PlayerPedId()), maxDistance)
end

function lib.getClosestObject(coords, maxDistance)
    return closestFromPool('CObject', coords or GetEntityCoords(PlayerPedId()), maxDistance)
end

-- ── Raycast (ox_lib's lib.raycast.fromCamera variant) ───────────────
lib.raycast = lib.raycast or {}
function lib.raycast.cam(flags, ignoreEntity, distance)
    local from = GetGameplayCamCoord()
    local rot  = GetGameplayCamRot(2)
    local rad  = math.pi / 180
    local z, x = rot.z * rad, rot.x * rad
    local cosX = math.abs(math.cos(x))
    local dir  = vector3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
    local to   = from + dir * (distance or 1000.0)
    local ray  = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, flags or -1,
        ignoreEntity or PlayerPedId(), 0)
    local _, hit, endCoords, surface, entity = GetShapeTestResult(ray)
    return hit == 1, endCoords, entity, surface
end
-- ox: lib.raycast.fromCoords / fromCamera aliases — wire both.
lib.raycast.fromCamera = lib.raycast.cam

-- ── addCommand / addKeybind ─────────────────────────────────────────
-- ox: lib.addCommand(name, opts, fn) — Atlas Commands.Add equivalent.
-- We only do this client-side stub here; the real registration is
-- server-side (chat-commands-need-server-registration memory). If a
-- consumer wants a client-only F8 binding, they can RegisterCommand
-- themselves — we don't fight that.
function lib.addCommand(name, opts, fn)
    RegisterCommand(name, function(source, args, raw)
        fn(source, args, raw)
    end, opts and opts.restricted or false)
    if opts and opts.help then
        TriggerEvent('chat:addSuggestion', '/' .. name, opts.help, opts.params)
    end
end

function lib.addKeybind(opts)
    if not opts or not opts.name or not opts.description or not opts.onPressed then
        return print('^3[ox_lib shim] lib.addKeybind: invalid opts^7')
    end
    RegisterCommand('+' .. opts.name, opts.onPressed, false)
    if opts.onReleased then RegisterCommand('-' .. opts.name, opts.onReleased, false) end
    RegisterKeyMapping('+' .. opts.name, opts.description, 'keyboard', opts.defaultKey or '')
end
