--------------------------------------------------------------------------
-- Module to extract Postgres Process Information for Boundary Lua Postgres Plugin
--
-- Author: Yegor Dia
-- Email: yegordia at gmail.com
--
--------------------------------------------------------------------------

local object = require('core').Object
local ffi = require("ffi")

--[[ Check os for binding library path
]]
if ffi.os == "Windows" then
	_G.POSTGRESQL_LIBRARY_PATH = ".\\windows-bindings\\lib\\x64\\pq"
end
postgresLuvit = require('luvit-postgres/postgresLuvit')


local function callIfNotNil(callback, ...)
    if callback ~= nil then
        callback(...)
    end
end

local PgInfo = object:extend()

--[[ Initialize PgInfo with connection parameters
]]
function PgInfo:initialize(host, port, user, pwd, database, source)
	self.connection_string = string.format("host=%s port=%s dbname=%s user=%s password=%s", host, port, database, user, pwd)
	p(string.format("connection string: %s", self.connection_string))
	return self
end

--[[ Establishing method required to be used before every query
]]
function PgInfo:establish(queries_callback)
	self.con = postgresLuvit:new(self.connection_string, function(err)
		assert(not err, err)
		callIfNotNil(queries_callback, self.con)
	end)
end

--[[ Test function
]]
function PgInfo:test()
	self:establish(function(connection)
	
		connection:sendQuery("DROP TABLE IF EXISTS test",function(err, res)
			assert(not err, err)

			connection:sendQuery("CREATE TABLE test (id bigserial primary key, content text, addedAt timestamp)",function(err, res)
				assert(not err, err)

				connection:sendQuery("INSERT INTO test (content, addedAt) VALUES (" .. 
									connection:escape([["); DROP TABLE test; --]]) ..
									", now() )",function(err, res)
					assert(not err, err)

					connection:sendQuery("SELECT * FROM test",function(err, res)
						assert(not err, err)
						p(res)
					end)
				end)
			end)
		end)
		
	end)
end

--[[ Get list of databases
]]
function PgInfo:get_databases()
	self:establish(function(connection)
	
		connection:sendQuery("SELECT datname FROM pg_database;",function(err, res)
			assert(not err, err)
			local dbs = {}
			for i, name in ipairs(res) do
				if name ~= "datname" then
					table.insert(dbs, name)
				end
			end
			
			return dbs
		end)
		
	end)
end

return PgInfo