package = "jsonrpc"
version = "scm-1"
source = {
    url = "git://github.com/r3l0c/jsonrpc.git"
}
description = {
    summary = "JSON-RPC 2.0 server and client for Tarantool",
    detailed = [[
        A complete JSON-RPC 2.0 implementation for Tarantool with separate
        server and client components that can be used with any transport layer.
    ]],
    homepage = "https://github.com/r3l0c/jsonrpc",
    license = "MIT"
}
dependencies = {
    "lua >= 5.1",
    "tarantool >= 2.0"
}
build = {
    type = 'builtin',
     modules = {
            ["jsonrpc.server"] = "jsonrlc/server.lua",
            ["jsonrpc.client"] = "jsonrlc/client.lua",
            ["jsonrpc.init"] = "jsonrlc/init.lua"
    }
}