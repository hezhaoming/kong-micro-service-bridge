local cjson = require "cjson"
local http = require "resty.http"
local ngx_re = require "ngx.re"
-- kong 管理工具类
local kongAdminOperation = require "kong.plugins.micro-service-bridge.admin.kongadminoperation"
local Dump = require "kong.plugins.micro-service-bridge.util.dump"
local Common = require "kong.plugins.micro-service-bridge.util.common"
-- 多个worker 共享的
local kong_cache = ngx.shared.kong
local pluginName = "micro-service-bridge"
local cacheKey = "sync_eureka_apps"
local eureka_suffix = 2
local METHOD_GET = "GET"
local cache_expire = 120
local sync_server_plugin = {}
local LOG_INFO = kong.log.info
local LOG_DEBUG = kong.log.debug
local LOG_ERROR = kong.log.err
-- eureka 服务发现
local EurekaServiceDiscovery = {}
EurekaServiceDiscovery.__index = EurekaServiceDiscovery
-- https://github.com/Netflix/eureka/wiki/Eureka-REST-operations
local status_weight = {
    ["UP"] = 100,
    ["DOWN"] = 1,
    ["STARTING"] = 0,
    ["OUT_OF_SERVICE"] = 0,
    ["UNKNOWN"] = 1
}

-- 请求注册服务中心服务列表
local function httpApps(httpClient, url, app_name)
    local path = url .. "/apps/" .. (app_name or '')
    print("\n" .. "=====请求注册中心的服务列表数据 starting...=====path====" .. path .. "\n")
    local res, err = httpClient:request_uri(path, {
        method = METHOD_GET,
        headers = { ["Accept"] = "application/json" },
        keepalive_timeout = 60,
        keepalive_pool = 10
    })
    if not res then
        LOG_ERROR("failed to fetch eureka apps request: ", err)
        print("\n" .. "=====请求注册中心的服务列表数据 ending...=====path====" .. path .. "err:" .. err .. "\n")
        return nil
    end
    local apps = cjson.decode(res.body)

    if apps then
        print("\n" .. "=====请求注册中心的服务列表数据 ending...=====apps:====" .. cjson.encode(apps) .. "\n")
    end

    return apps
end
-- 处理服务的结果集
local function handleApps(apps, excludes, tags, app_name)
    --[[
         convert to app_list
         -- https://github.com/Netflix/eureka/wiki/Eureka-REST-operations
         {
         "demo":{
           "192.168.0.10:8080"="UP",
           "health_path"="/health"
         }
       }
     ]]
    -- 如果是单个拉取服务配置
    if app_name then
        apps = { ["applications"] = { ["application"] = { apps["application"] } } }
    end

    local app_list = {}
    for _, item in pairs(apps["applications"]["application"]) do
        -- eureka 的注册中心会将服务名变成全大写,这里统一小写
        local name = string.lower(item["name"])
        -- 剔除非暴露的服务实例
        if Common.is_not_include(name, excludes) then
            app_list[name] = {}
            for _, it in pairs(item["instance"]) do
                -- homePageUrl 切割地址 target
                local host, _ = ngx_re.split(it["homePageUrl"], "/")
                --tags
                app_list[name]["tags"] = tags
                -- 服务实例状态 UP
                app_list[name][host[3]] = it['status']
                -- 截取监控检查地址
                app_list[name]["health_path"] = string.sub(it["healthCheckUrl"], string.len(it["homePageUrl"]))
            end
        end
    end
    LOG_DEBUG("end to fetch eureka apps,total of ", #app_list, " apps")
    return app_list
end

--- fetch eureka applications info
local function eureka_apps(app_name)
    print("\n" .. "================开始 http 拉取 eureka apps 服务列表...=================" .. "\n")
    LOG_INFO("start fetch eureka apps [ ", app_name or "all", " ]")
    if not sync_server_plugin then
        return nil, 'failed to query plugin config'
    end
    local config = sync_server_plugin["enabled"] and sync_server_plugin["config"] and sync_server_plugin["config"]["eurekaJSON"] or {}

    -- 配置的服务列表
    local serviceList = cjson.decode(config).serviceList
    local app_list = {}
    print("\n" .. "================开始 http 拉取 eureka apps 服务列表...=================config==>>>" .. cjson.encode(serviceList) .. "\n")
    -- 如果配置列表存在，那么则遍历拉取各个注册中心的服务
    if serviceList then
        --[[
         -- 统一配置数据结构
         -- {
         -- "serviceList":[{"url":["","",""],"tag":"bbc","exclude":["","",""]}],
         -- "syncInterval":"10",
         -- "cleanTargetInterval":"80"
         -- }
         --
         --]]
        local httpClient = http.new()
        for i, service in ipairs(serviceList) do
            local excludes = service.exclude;
            local tags = service.tags;
            local urls = service.url;
            -- 注册中心集群取一个即可
            local apps = nil
            -- 轮询请求注册中心的数据，有则跳出循环，处理数据，否则，尝试下一个url，直到尝试完毕
            for i, url in ipairs(urls) do
                apps = httpApps(httpClient, url, app_name)
                if apps then
                    break
                end
            end
            app_list = handleApps(apps, excludes, tags, app_name)
        end
    end

    return app_list

end

-- 同步注册中心列表
EurekaServiceDiscovery.sync_list_job = function(app_name)
    print("\n" .. "定时任务开始同步注册中心列表......" .. "\n")
    -- 拉取最新的配置
    sync_server_plugin = kongAdminOperation.getCurrentPlugin(pluginName)
    -- 如果不存在则不拉取数据
    if not sync_server_plugin then
        return
    end
    -- 1.先从缓存拉取 服务注册列表
    local cache_app_list = kong_cache:get(cacheKey) or "{}"
    -- 缓存中的 服务列表
    cache_app_list = cjson.decode(cache_app_list)
    -- 拉取最新的服务列表，ps：注意这里已经将非暴露的服务剔除
    local app_list = eureka_apps(app_name)
    print("\n" .. "解析好的 eureka 服务列表app_list" .. cjson.encode(app_list) .. "cache_app_list" .. cjson.encode(cache_app_list))
    -- 遍历服务列表
    for name, item in pairs(app_list) do
        -- 如果缓存中不存在该服务则创建
        if not cache_app_list[name] then
            -- 所有的操作，只做加法，不做减法（安全考虑）
            kongAdminOperation.create_service(cacheKey, name, item.tags, eureka_suffix)
            kongAdminOperation.create_route(cacheKey, name, item.tags)
            kongAdminOperation.create_upstream(cacheKey, name, item.tags, eureka_suffix)
        end
        -- 创建成功后，然后更新缓存标志   
        cache_app_list[name] = true
        -- 遍历服务的target
        for target, status in pairs(item) do
            -- 如果不是target 不健康则set
            if target ~= "health_path" then
                kongAdminOperation.put_target(cacheKey, name, target, status_weight[status], { status }, eureka_suffix)
            end
        end
    end
    -- 最后存入缓存
    kong_cache:safe_set(cacheKey, cjson.encode(cache_app_list), cache_expire)
end
-- 定时摘除 心跳失败的服务实例
EurekaServiceDiscovery.cleanup_list_targets = function()
    print("\n" .. "定时摘除 心跳失败的服务实例......")
    sync_server_plugin = kongAdminOperation.getCurrentPlugin(pluginName)
    if not sync_server_plugin then
        return
    end
    local app_list = eureka_apps()
    local upstreams = kongAdminOperation.kong_upstreams(nil, eureka_suffix) or {}
    for up_name, name in pairs(upstreams) do
        local targets = kongAdminOperation.get_targets(cacheKey, name, "/upstreams/" .. up_name .. "/targets") or {}
        -- delete all targets by this upstream name
        if not app_list[name] then
            for target, _ in pairs(targets) do
                kongAdminOperation.delete_target(cacheKey, name, target, eureka_suffix)
            end
        else
            for target, _ in pairs(targets) do
                -- delete this target 即 不是up的服务都是不健康的
                if app_list[name][target] ~= "UP" then
                    kongAdminOperation.delete_target(cacheKey, name, target, eureka_suffix)
                end
            end
        end
    end
end

return EurekaServiceDiscovery
