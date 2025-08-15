# Tarantool JSON-RPC 2.0 Library

## Overview

A lightweight, transport-agnostic JSON-RPC 2.0 implementation for Tarantool that provides complete server and client functionality. Designed for seamless integration with any communication protocol (HTTP, WebSocket, TCP, etc.) while maintaining full JSON-RPC 2.0 specification compliance.


## Features

- **Full JSON-RPC 2.0 Specification Support**
- **Transport Agnostic Design** - Works with any protocol
- **Middleware Support** - For authentication, logging, and request transformation
- **Batch Processing** - Handle multiple requests efficiently
- **Lightweight** - Minimal overhead
- **Simple API** - Easy integration into existing projects
- **Error Handling** - Comprehensive error codes and messages

## Documentation

[LDoc HTML](https://htmlpreview.github.io/?https://github.com/r3l0c/jsonrpc/blob/master/docs/index.html)


## Installation

```bash
tt rocks install https://raw.githubusercontent.com/r3l0c/jsonrpc/refs/heads/master/websocket-scm-1.rockspec
```

## Server Usage

### Basic Setup
```lua
local json = require('json')
local rpc_server = require('rpc.server').new()

-- Register methods
rpc_server:register('greet', function(name)
    return "Hello, " .. (name or "World") .. "!"
end)

rpc_server:register('add', function(a, b)
    return a + b
end)

-- Add authentication middleware
rpc_server:use(function(request)
    local token = request.headers and request.headers.Authorization
    if not token or token ~= "secret-token" then
        return false, {
            code = 401,
            message = "Unauthorized"
        }
    end
    return true
end)

-- Process request
local request = [[
{
    "jsonrpc": "2.0",
    "method": "greet",
    "params": ["Alice"],
    "id": 1
}
]]

local response = rpc_server:receive(request)
print(response)
-- {"jsonrpc":"2.0","result":"Hello, Alice!","id":1}
```

## Client Usage

### Creating Requests
```lua
local json = require('json')
local rpc_client = require('rpc.client').new()

-- Add request logging middleware
rpc_client:use(function(request)
    print("Sending request:", request.method)
    return request
end)

-- Create call request
local request_id, call_request = rpc_client:create_call('get_user', {id = 123})
call_request.headers = {Authorization = "token"}

-- Create notification
local notify_request = rpc_client:create_notify('log_event', {event = "connected"})

-- Register response handler
rpc_client:register_handler(request_id, function(response)
    if response.error then
        print("Error:", response.error.message)
    else
        print("User data:", json.encode(response.result))
    end
end)
```

## Transport Examples

### WebSocket Transport

**Server:**
```lua
local websocket = require('websocket')
local json = require('json')
local rpc_server = require('rpc.server').new()

-- Register methods
rpc_server:register('echo', function(text)
    return text
end)

-- Start WebSocket server
websocket.server('0.0.0.0', 8080, {
    on_message = function(ws, message)
        local response = rpc_server:receive(message)
        ws:write(response)
    end
})
```

**Client:**
```lua
local websocket = require('websocket')
local json = require('json')
local rpc_client = require('rpc.client').new()

-- Connect to WebSocket server
local ws = websocket.connect('ws://localhost:8080')

-- Create and send request
local request_id, request = rpc_client:create_call('echo', {"Hello WebSocket!"})
ws:write(json.encode(request))

-- Register response handler
rpc_client:register_handler(request_id, function(response)
    print("Response:", response.result)
end)

-- Process messages
while true do
    local message = ws:read()
    if message then
        rpc_client:receive(message)
    end
    fiber.sleep(0.1)
end
```

### HTTP Transport

**Server:**
```lua
local httpd = require('http.server')
local json = require('json')
local rpc_server = require('rpc.server').new()

-- Register methods
rpc_server:register('multiply', function(a, b)
    return a * b
end)

-- Create HTTP server
local server = httpd.new('0.0.0.0', 8080)


-- Add RPC endpoint
server:route({
    path = '/rpc',
    method = 'POST'
}, function(req)
    local response = rpc_server:receive(req:read_body())
    return req:render({
        status = 200,
        body = response
    })
end)

-- Start server
server:start()
```

## Advanced Features

### Batch Processing
```lua
-- Server
local responses = rpc_server:receive_batch({
    '{"jsonrpc":"2.0","method":"method1","id":1}',
    '{"jsonrpc":"2.0","method":"method2","id":2}'
})

-- Client
local requests = {
    rpc_client:create_call('method1', {param1 = "value1"}),
    rpc_client:create_call('method2', {param2 = "value2"})
}

-- Send batch request
ws:write(json.encode(requests))
```

### Middleware Examples

**Server (Authentication):**
```lua
rpc_server:use(function(request)
    -- JWT verification
    local token = request.headers.Authorization
    if not verify_jwt(token) then
        return false, {
            code = 403,
            message = "Invalid token"
        }
    end
    return true
end)
```

**Client (Request Signing):**
```lua
rpc_client:use(function(request)
    -- Add HMAC signature
    local payload = json.encode(request.params)
    request.headers['X-Signature'] = hmac_sha256(payload, secret_key)
    return request
end)
```

**Server (Rate Limiting):**
```lua
local rate_limits = {}

rpc_server:use(function(request)
    local ip = request.client_ip
    rate_limits[ip] = (rate_limits[ip] or 0) + 1
    
    if rate_limits[ip] > 100 then
        return false, {
            code = 429,
            message = "Too many requests"
        }
    end
    return true
end)
```