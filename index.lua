local boundary = require('boundary')
local pginfo = require('pginfo')

-- Default params
local host = "localhost"
local port = 5432
local user = "postgres"
local pwd = ""
local database = "postgres"
local source = ""

-- Fetching params
if (boundary.param ~= nil) then
  host = boundary.param['host'] or host
  port = boundary.param['port'] or port
  user = boundary.param['user'] or user
  pwd = boundary.param['pwd'] or pwd
  database = boundary.param['database'] or database
  source = boundary.param['source'] or source
end

print("_bevent:Boundary LUA Postgres plugin up : version 1.0|t:info|tags:lua,plugin")

local dbcon = pginfo:new(host, port, user, pwd, database, source)
print(dbcon:get_databases())

