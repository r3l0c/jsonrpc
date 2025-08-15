local t = require('luatest')
local client = require('jsonrpc.client')
local json = require('json')
local uuid = require('uuid')

local g = t.group('test_client')

g.test_create_call = function()
    local rpc_client = client.new()

    -- Add middleware to capture the request
    local captured_request
    rpc_client:use(function(request)
        captured_request = request
        return request
    end)

    local method = "add"
    local params = { 2, 3 }
    local request_id, request = rpc_client:create_call(method, params)

    t.assert_not_equals(request_id, nil)
    t.assert_equals(type(request_id), 'string')
    t.assert_equals(request.jsonrpc, "2.0")
    t.assert_equals(request.method, method)
    t.assert_equals(request.params, params)
    t.assert_equals(request.id, request_id)

    -- Verify middleware was applied
    t.assert_equals(captured_request, request)
end

g.test_create_notify = function()
    local rpc_client = client.new()

    -- Add middleware to capture the request
    local captured_request
    rpc_client:use(function(request)
        captured_request = request
        return request
    end)

    local method = "notify"
    local params = { "some event" }
    local request = rpc_client:create_notify(method, params)

    t.assert_equals(request.jsonrpc, "2.0")
    t.assert_equals(request.method, method)
    t.assert_equals(request.params, params)
    t.assert_is(request.id, nil)

    -- Verify middleware was applied
    t.assert_equals(captured_request, request)
end

g.test_middleware = function()
    local rpc_client = client.new()

    -- Middleware that adds a header
    rpc_client:use(function(request)
        request.headers = { Authorization = "Bearer token" }
        return request
    end)

    -- Additional middleware that modifies parameters
    rpc_client:use(function(request)
        if request.method == "add" then
            request.params = { request.params[1] + 1, request.params[2] + 1 }
        end
        return request
    end)

    -- Test call
    local _, call_request = rpc_client:create_call('add', { 1, 2 })
    t.assert_equals(call_request.headers.Authorization, "Bearer token")
    t.assert_equals(call_request.params, { 2, 3 })

    -- Test notify
    local notify_request = rpc_client:create_notify('log', { "message" })
    t.assert_equals(notify_request.headers.Authorization, "Bearer token")
end

g.test_success_response_handling = function()
    local rpc_client = client.new()

    -- Create a request
    local request_id, request = rpc_client:create_call('get_data')

    -- Register handler
    local received_response
    rpc_client:register_handler(request_id, function(response)
        received_response = response
    end)

    -- Create a successful response
    local success_response = {
        jsonrpc = "2.0",
        result = "success",
        id = request_id
    }

    -- Process response
    rpc_client:receive(json.encode(success_response))
    t.assert_equals(received_response.result, "success")
end

g.test_error_response_handling = function()
    local rpc_client = client.new()

    -- Create a request
    local request_id, request = rpc_client:create_call('get_data')

    -- Register handler
    local received_response
    rpc_client:register_handler(request_id, function(response)
        received_response = response
    end)

    -- Create an error response
    local error_response = {
        jsonrpc = "2.0",
        error = {
            code = -32000,
            message = "Error message"
        },
        id = request_id
    }

    -- Process response
    rpc_client:receive(json.encode(error_response))
    t.assert_equals(received_response.error.message, "Error message")
end

g.test_batch_response_handling = function()
    local rpc_client = client.new()

    -- Create requests
    local id1, req1 = rpc_client:create_call('method1')
    local id2, req2 = rpc_client:create_call('method2')

    -- Register handlers
    local responses = {}
    rpc_client:register_handler(id1, function(resp) responses[1] = resp end)
    rpc_client:register_handler(id2, function(resp) responses[2] = resp end)

    -- Create responses
    local resp1 = json.encode({ jsonrpc = "2.0", result = "result1", id = id1 })
    local resp2 = json.encode({ jsonrpc = "2.0", result = "result2", id = id2 })

    -- Process batch
    rpc_client:receive_batch({ resp1, resp2 })

    t.assert_equals(responses[1].result, "result1")
    t.assert_equals(responses[2].result, "result2")
end

g.test_response_without_handler = function()
    local rpc_client = client.new()

    -- Create response for unregistered request
    local response = {
        jsonrpc = "2.0",
        result = "data",
        id = uuid.str() -- random ID
    }

    -- Should return the response
    local result = rpc_client:receive(json.encode(response))
    t.assert_equals(result.result, "data")
end

g.test_invalid_json_response = function()
    local rpc_client = client.new({ log_errors = false })

    -- Process invalid JSON
    local result = rpc_client:receive("invalid json")
    t.assert_equals(result, false)
end

g.test_middleware_chain = function()
    local rpc_client = client.new()
    local calls = {}

    -- Add multiple middleware
    rpc_client:use(function(req)
        table.insert(calls, 1)
        req.order = 1
        return req
    end)

    rpc_client:use(function(req)
        table.insert(calls, 2)
        req.order = 2
        return req
    end)

    rpc_client:use(function(req)
        table.insert(calls, 3)
        req.order = 3
        return req
    end)

    -- Create request
    local _, request = rpc_client:create_call('test')

    -- Verify middleware execution order
    t.assert_equals(calls, { 1, 2, 3 })
    t.assert_equals(request.order, 3)
end
