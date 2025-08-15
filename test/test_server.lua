local t = require('luatest')
local server = require('jsonrpc.server')
local json = require('json')
local log = require('log')

local g = t.group('test_server')

g.test_basic_call = function()
    local rpc_server = server.new()
    rpc_server:register('add', function(a, b) return a + b end)

    local request = {
        jsonrpc = "2.0",
        method = "add",
        params = { 2, 3 },
        id = 1
    }
    local response_str = rpc_server:receive(json.encode(request))
    local response = json.decode(response_str)

    t.assert_equals(response.result, 5)
    t.assert_equals(response.id, 1)
end

g.test_method_not_found = function()
    local rpc_server = server.new()
    local request = {
        jsonrpc = "2.0",
        method = "unknown_method",
        params = {},
        id = 1
    }
    local response_str = rpc_server:receive(json.encode(request))
    local response = json.decode(response_str)

    t.assert_equals(response.error.code, -32601)
    t.assert_equals(response.error.message, "Method not found")
end

g.test_parse_error = function()
    local rpc_server = server.new()
    local response_str = rpc_server:receive("invalid json")
    local response = json.decode(response_str)

    t.assert_equals(response.error.code, -32700)
    t.assert_equals(response.error.message, "Parse error")
end

g.test_middleware_deny = function()
    local rpc_server = server.new()
    rpc_server:register('add', function(a, b) return a + b end)

    -- Middleware that always denies access
    rpc_server:use(function()
        return false
    end)

    local request = {
        jsonrpc = "2.0",
        method = "add",
        params = { 2, 3 },
        id = 1
    }
    local response_str = rpc_server:receive(json.encode(request))
    local response = json.decode(response_str)

    t.assert_equals(response.error.code, -32603)
    t.assert_equals(response.error.message, "Internal error")
end

g.test_middleware_custom_error = function()
    local rpc_server = server.new()
    rpc_server:register('add', function(a, b) return a + b end)

    -- Middleware that returns custom error
    rpc_server:use(function()
        return false, { code = -32099, message = "Custom error", data = "Forbidden" }
    end)

    local request = {
        jsonrpc = "2.0",
        method = "add",
        params = { 2, 3 },
        id = 1
    }
    local response_str = rpc_server:receive(json.encode(request))
    local response = json.decode(response_str)

    t.assert_equals(response.error.code, -32099)
    t.assert_equals(response.error.message, "Custom error")
    t.assert_equals(response.error.data, "Forbidden")
end

g.test_access_control_middleware_allow = function()
    local rpc_server = server.new()
    rpc_server:register('add', function(a, b) return a + b end)

    -- Middleware that always allows access
    rpc_server:use(function()
        return true
    end)

    local request = {
        jsonrpc = "2.0",
        method = "add",
        params = { 2, 3 },
        id = 1
    }
    local response_str = rpc_server:receive(json.encode(request))
    local response = json.decode(response_str)

    t.assert_equals(response.result, 5)
end

g.test_metadata_access_in_middleware = function()
    local rpc_server = server.new()
    rpc_server:register('admin_action', function() return "OK" end, { role = "admin" })

    local called = false
    rpc_server:use(function(request, method_meta)
        called = true
        t.assert_equals(method_meta.metadata.role, "admin")
        return true
    end)

    local request = {
        jsonrpc = "2.0",
        method = "admin_action",
        id = 1
    }
    rpc_server:receive(json.encode(request))

    t.assert(called, "Middleware should be called")
end
