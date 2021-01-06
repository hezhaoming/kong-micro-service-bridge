-- hello-world.handlar.lua
local BasePlugin = require "kong.plugins.base_plugin"
local ServerDiscovery = require "kong.plugins.micro-service-bridge.serverdiscovery"

local MicroServiceBridge = BasePlugin:extend()

MicroServiceBridge.VERSION = "1.0.0"
MicroServiceBridge.PRIORITY = 10


-- 插件构造函数
function MicroServiceBridge:new()
    MicroServiceBridge.super.new(self, "micro-service-bridge")
    print("插件构建成功..micro-service-bridge....")
    kong.log.notice("-----MicroServiceBridge-new----starting--")
end

function MicroServiceBridge:init_worker()
    MicroServiceBridge.super.init_worker(self)
    kong.log.notice("-----微服务自动注册启动........--")
    ServerDiscovery.starting()
end

return MicroServiceBridge

