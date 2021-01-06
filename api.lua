local EurekaServiceDiscovery = require "kong.plugins.micro-service-bridge.eureka.eurekaservicediscovery"
local ServerDiscovery = require "kong.plugins.micro-service-bridge.serverdiscovery"
local write = kong.response.exit
return {
    ["/eureka/sync(/:app)"] = {
        POST = function(self)
            EurekaServiceDiscovery.sync_list_job(self.params.app)
            return write(200, { message = "sync eureka " .. (self.params.app or "all") .. " now ..." })
        end
    },
    ["/eureka/clean-targets"] = {
        POST = function()
            EurekaServiceDiscovery.cleanup_list_targets()
            return write(200, { message = "cleanup invalid targets ..." })
        end
    },
    ["/server/discovery/starting"] = {
        GET = function()
            ServerDiscovery.starting()
            return write(200, { message = "micro-service-bridge starting ..." })
        end
    }
}
