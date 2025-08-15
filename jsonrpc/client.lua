--- @module rpc.client
-- JSON-RPC 2.0 client implementation for Tarantool
-- Provides a flexible and transport-agnostic RPC client
-- that can be integrated with any communication protocol.

local json = require('json')
local log = require('log')
local uuid = require('uuid')

local client = {}

local DEFAULT_OPTIONS = {
    log_errors = true,
}

--- Create a new RPC client instance
--- @function client.new
--- @param ?options table Configuration options (optional)
--- @return table client client instance
function client.new(options)
    options = options or {}
    local self = setmetatable({
        options = setmetatable({}, { __index = DEFAULT_OPTIONS }),
        middlewares = {},
        callbacks = {},
    }, { __index = client })

    for k, v in pairs(options) do
        self.options[k] = v
    end

    return self
end

--- Add middleware for request processing
-- Middleware function signature:
-- `function(request): request`
--
--- @function client:use
--- @param middleware function Middleware function to add
function client:use(middleware)
    if type(middleware) ~= 'function' then
        error("middleware must be a function", 2)
    end
    table.insert(self.middlewares, middleware)
end

--- Apply middleware to a request
--- @local
--- @param self client instance
--- @param request table RPC request
--- @return table Processed request
local function apply_middleware(self, request)
    for _, middleware in ipairs(self.middlewares) do
        request = middleware(request)
    end
    return request
end

--- Create a JSON-RPC call request
--- @function client:create_call
--- @param method string RPC method name
--- @param ?params table Method parameters (optional)
--- @return string request_id Unique request identifier
--- @return table request_table Prepared request table
function client:create_call(method, params)
    if type(method) ~= 'string' then
        error("method must be a string", 2)
    end

    local request_id = uuid.str()
    local request = {
        jsonrpc = "2.0",
        method = method,
        params = params or {},
        id = request_id,
    }

    return request_id, apply_middleware(self, request)
end

--- Create a JSON-RPC notification request
--- @function client:create_notify
--- @param method string RPC method name
--- @param ?params table Method parameters (optional)
--- @return table request_table Prepared request table
function client:create_notify(method, params)
    if type(method) ~= 'string' then
        error("method must be a string", 2)
    end

    local request = {
        jsonrpc = "2.0",
        method = method,
        params = params or {},
    }

    return apply_middleware(self, request)
end

--- Register a response handler
--- @function client:register_handler
--- @param request_id string Request identifier
--- @param handler function Response handler function
function client:register_handler(request_id, handler)
    if type(handler) ~= 'function' then
        error("handler must be a function", 2)
    end
    self.callbacks[request_id] = handler
end

--- Process incoming response
--- @function client:receive
--- @param response_str string JSON-RPC response string
--- @return table|boolean Processed response or false on error
function client:receive(response_str)
    local status, response = pcall(json.decode, response_str)
    if not status then
        if self.options.log_errors then
            log.error("RPC response parse error: %s", tostring(response))
        end
        return false
    end

    -- Process registered handler
    if response.id and self.callbacks[response.id] then
        local handler = self.callbacks[response.id]
        self.callbacks[response.id] = nil
        handler(response)
    end

    return response
end

--- Process batch of responses
--- @function client:receive_batch
--- @param responses table Array of JSON-RPC response strings
--- @return table Array of processed responses
function client:receive_batch(responses)
    local results = {}
    for _, response_str in ipairs(responses) do
        table.insert(results, self:receive(response_str))
    end
    return results
end

return client