return {
    name = "micro-service-bridge",
    fields = {
        {
            config = {
                type = "record",
                fields = {
                    { zookeeperJSON = { type = "string" } },
                    { eurekaJSON = { type = "string" } },
                    { simpleJSON = { type = "string" } }
                }
            }
        }
    }
}


--{
--    "serviceList": [{
--        "url": ["http://10.10.220.132:9001/eureka", "", ""],
--    "tags": ["bbc"],
--    "exclude": ["", "", ""]
--}],
--"syncInterval": "10",
--"cleanTargetInterval": "80"
--}
-- 统一配置数据结构
-- {
-- "serviceList":[{"url":["","",""],"tag":"bbc","exclude":["","",""]}],
-- "syncInterval":"10",
-- "cleanTargetInterval":"80"
-- }
--

