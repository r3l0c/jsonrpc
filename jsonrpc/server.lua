---------------------------
-- @module rpc.server
-- JSON-RPC 2.0 server implementation for Tarantool
-- Provides a flexible and transport-agnostic RPC server
-- that can be integrated with any communication protocol.
local json = require('json')
local log = require('log')



local server = {}

local DEFAULT_OPTIONS = {
    log_errors = true,
}

--- Build a JSON-RPC error response
--- @local
--- @function build_error_response
--- @param id string|number|nil Request identifier (optional)
--- @param error_data table Error information
--- @return string JSON-encoded error response
local function build_error_response(id, error_data)
    return json.encode({
        jsonrpc = "2.0",
        error = {
            code = error_data.code or -32000,
            message = error_data.message or "Unauthorized",
            data = error_data.data
        },
        id = id
    })
end

--- Process incoming JSON-RPC request
--- @local
--- @function process_request
--- @param self server instance
--- @param request table Decoded JSON-RPC request
--- @return string JSON-encoded response
local function process_request(self, request)
    -- Validate JSON-RPC 2.0 structure
    if request.jsonrpc ~= "2.0" then
        return build_error_response(request.id, {
            code = -32600,
            message = "Invalid Request",
            data = "jsonrpc must be '2.0'"
        })
    end

    if not request.method then
        return build_error_response(request.id, {
            code = -32600,
            message = "Invalid Request",
            data = "method is required"
        })
    end

    local method = self.methods[request.method]
    if not method then
        return build_error_response(request.id, {
            code = -32601,
            message = "Method not found",
            data = "Method '" .. request.method .. "' not registered"
        })
    end

    -- Execute the method
    local params = request.params or {}

    local ok, result, result_err = pcall(function()
        return method.func(unpack(params))
    end)

    if not ok then
        if self.options.log_errors then
            log.error("RPC error in method %s: %s", request.method, tostring(result))
        end

        return build_error_response(request.id, {
            code = -32603,
            message = "Internal error",
            data = tostring(result)
        })
    end

    if result_err ~= nil then
        return build_error_response(request.id, {
            code = result_err.code or -32000,
            message = result_err.message or "Application error",
            data = result_err.data
        })
    end

    return json.encode({
        jsonrpc = "2.0",
        result = result,
        id = request.id
    })
end

--- Create a new RPC server instance
--- @function server.new
--- @param ?options table Configuration options (optional)
--- @return table server server instance
function server.new(options)
    options = options or {}
    local self = setmetatable({
        methods = {},
        options = setmetatable({}, { __index = DEFAULT_OPTIONS }),
        middlewares = {},
    }, { __index = server })

    for k, v in pairs(options) do
        self.options[k] = v
    end

    return self
end

--- Register an RPC method
--- @function server:register
--- @param method_name string Name of the method to register
--- @param func function Function to execute for this method
--- @param metadata table Method metadata (optional)
--- @return boolean true on success
function server:register(method_name, func, metadata)
    if type(func) ~= 'function' then
        error("func must be a function", 2)
    end

    self.methods[method_name] = {
        func = func,
        metadata = metadata or {}
    }

    return true
end

--- Register multiple methods at once
--- @function server:register_methods
--- @param methods table Key-value pairs of method names and functions
function server:register_methods(methods)
    for name, func in pairs(methods) do
        self:register(name, func)
    end
end

--- Add middleware for request processing
-- Middleware function signature:
-- `function(request, method_metadata): ok, error_data`
--
-- Where:
--   request: JSON-RPC request table
--   method_metadata: Metadata for the requested method (if available)
--   ok: boolean (true = continue processing, false = reject request)
--   error_data: table|nil Error details when rejecting (optional)
--
--- @function server:use
--- @param middleware function Middleware function to add
function server:use(middleware)
    if type(middleware) ~= 'function' then
        error("middleware must be a function", 2)
    end
    table.insert(self.middlewares, middleware)
end

--- Process incoming message
--- @function server:receive
--- @param message string JSON-RPC request string
--- @return string JSON-encoded response
function server:receive(message)
    local status, request = pcall(json.decode, message)
    if status == false then
        return build_error_response(nil, {
            code = -32700,
            message = "Parse error",
            data = tostring(request)
        })
    end

    for _, middleware in ipairs(self.middlewares) do
        local ok, error_data = middleware(request, self.methods[request.method])

        if ok == false then
            return build_error_response(request.id, error_data and error_data or {
                code = -32603,
                message = "Internal error",
                data = "Invalid middleware response"
            })
        end
    end

    return process_request(self, request)
end

--- Process batch of messages
--- @function server:receive_batch
--- @param messages table Array of JSON-RPC request strings
--- @return table Array of JSON-encoded responses
function server:receive_batch(messages)
    local responses = {}
    for _, message in ipairs(messages) do
        table.insert(responses, self:receive(message))
    end
    return responses
end

return server
