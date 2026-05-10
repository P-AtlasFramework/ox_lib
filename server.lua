-- ox_lib server overlay — callback registration + Atlas Command bridge.

-- ── Callbacks ───────────────────────────────────────────────────────
-- ox: lib.callback.register('name', fn) — server registers a server
-- callback the client triggers via lib.callback(...). Routes through
-- atlas_core's Functions.CreateCallback.
local Atlas
CreateThread(function()
    while not Atlas do
        local ok, core = pcall(function() return exports['atlas_core']:GetCoreObject() end)
        if ok and core then Atlas = core end
        Wait(150)
    end
end)

lib.callback = setmetatable({}, {
    __call = function(_, name, source, cb, ...)
        -- Server -> client callbacks aren't part of ox_lib's
        -- mainstream surface (they're via lib.callback to client
        -- by id). Atlas exposes this via TriggerClientCallback;
        -- we forward when available, else warn.
        if Atlas and Atlas.Functions.TriggerClientCallback then
            Atlas.Functions.TriggerClientCallback(name, source, cb, ...)
        else
            print('^3[ox_lib shim] server->client callback not supported: '..tostring(name)..'^7')
            if cb then cb() end
        end
    end,
})

---@diagnostic disable-next-line: duplicate-set-field
function lib.callback.register(name, fn)
    -- atlas_core: Atlas.Functions.CreateCallback(name, function(source, reply, ...) reply(...) end)
    -- ox_lib: lib.callback.register(name, function(source, ...) return ... end)
    -- Adapter wraps the ox signature into atlas's reply pattern.
    CreateThread(function()
        while not Atlas do Wait(50) end
        Atlas.Functions.CreateCallback(name, function(source, reply, ...)
            reply(fn(source, ...))
        end)
    end)
end

-- ── Commands ───────────────────────────────────────────────────────
-- ox: lib.addCommand(name, opts, fn) — registers with chat suggestions.
function lib.addCommand(name, opts, fn)
    opts = opts or {}
    CreateThread(function()
        while not Atlas do Wait(50) end
        Atlas.Commands.Add(name,
            opts.help or '',
            opts.params or {},
            opts.required or false,
            fn,
            opts.restricted or nil)
    end)
end

-- ── Notify (server-side trigger) ───────────────────────────────────
-- Already on lib in init.lua; this just adds the source-relay form
-- some ox resources use: `lib.notify(source, opts)`.
local origNotify = lib.notify
---@diagnostic disable-next-line: duplicate-set-field
function lib.notify(arg1, arg2)
    if type(arg1) == 'number' and type(arg2) == 'table' then
        arg2.source = arg1
        return origNotify(arg2)
    end
    return origNotify(arg1)
end
