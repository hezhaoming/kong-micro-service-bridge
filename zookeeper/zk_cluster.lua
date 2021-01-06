
local zk = require "kong.plugins.micro-service-bridge.zookeeper.zk"
local tablen = table.getn
local strsub = string.sub
local now = ngx.now
local sleep = ngx.sleep
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR

local _M = { __version = "0.01" }

local mt = { __index = _M }

function _M.new(self, config)
    if not self.inited then
        self.child_getting_state = {}
        self.data_getting_state = {}
        self.robin=0
        self.child_cache = {}
        self.data_cache = {}
        self.inited = true
        log(DEBUG, "initt......")
    end
    local timeout = config.timeout or 1000
    local expire = config.expire or 1
    return setmetatable({
        serv_list=config.serv_list,
        timeout=timeout,
        expire=expire
    }, mt)
end

function _M._get_host(self)
    local serv_list = self.serv_list
    local index = self.robin % tablen(serv_list)  + 1
    self.robin = self.robin + 1
    return serv_list[index]
end

function _M._connect(self)
    local conn = zk:new()
    conn:set_timeout(self.timeout)
    for i=1, #self.serv_list do
        local host = self:_get_host()
        local ok, err = conn:connect(host)
        if not ok then
            log(ERR, "connect ", host, " error ", err)
        else
            self.conn = conn
            return conn
        end
    end
    return nil
end

function _M._common_get(self, path, get_type, use_cache)
    local use_cache = use_cache or true
    local expire = self.expire
    local cache = nil
    local getting_state = nil
    local res
    local err

    if get_type == 'child' then
        cache = self.child_cache
        getting_state = self.child_getting_state
    elseif get_type == 'data' then
        cache = self.data_cache
        getting_state = self.data_getting_state
    end

    local getting = getting_state[path]
    if use_cache then
        local c = cache[path]
        if c then
            local value = c['v']
            if now() - c['expire'] < expire then
                log(DEBUG, "hit cache")
                return value
            else
                if getting then
                    log(DEBUG, "already getting, use stale cache")
                    return value
                else
                    log(DEBUG, "cache expired, freshing")
                    getting_state[path] = true
                    if get_type == 'child' then
                        res, err = self:_get_children(path)
                    elseif get_type == 'data' then
                        res, err = self:_get_data(path)
                    end
                    getting_state[path] = false
                    if res then
                        return res
                    else
                        return value
                    end
                end
            end
        else
            if getting then
                log(DEBUG, "already getting, sleep 1 seconds")
                sleep(1)
                c = cache[path]
                return c['v']
            else
                log(DEBUG, "first get")
                getting_state[path] = true
                if get_type == 'child' then
                    res, err = self:_get_children(path)
                elseif get_type == 'data' then
                    res, err = self:_get_data(path)
                end
                getting_state[path] = false
                return res
            end
        end
    else
        if get_type == 'child' then
            return self:_get_children(path)
        elseif get_type == 'data' then
            return self:_get_data(path)
        end
    end
end

function _M.get_children(self, path, use_cache)
    return self:_common_get(path, 'child', use_cache)
end

function _M._get_children(self, path)
    local conn = self.conn
    if not conn then
        conn = self:_connect()
        if not conn then
            return nil, "connect error"
        end
    end

    local res, err = conn:get_children(path)
    if not res then
        conn:close()
        self.conn = nil
        return nil, err
    end
    local c = {v=res, expire=now()}
    self.child_cache[path] = c
    return res
end

function _M.get_data(self, path, use_cache)
    return self:_common_get(path, 'data', use_cache)
end

function _M._get_data(self, path)
    local conn = self.conn
    if not conn then
        conn = self:_connect()
        if not conn then
            return nil, "connect error"
        end
    end
    local res, err = conn:get_data(path)
    if not res then
        conn:close()
        self.conn = nil
        return nil, err
    end
    local c = {v=res, expire=now()}
    self.data_cache[path] = c
    return res
end

return _M

