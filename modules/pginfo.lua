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

local function createDictWithKeys(keys, default_val)
	local dict = {}
	local default = nil
	
	if default_val ~= nil then
		default = default_val
	end
	
	for i, name in ipairs(keys) do
		dict[name] = default
	end
	return dict
end

local function createDictWithKeysAndValues(keys, values)
	local dict = {}
	
	for i, name in ipairs(keys) do
		dict[name] = values[i]
	end
	return dict
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local PgInfo = object:extend()

--[[ Initialize PgInfo with connection parameters
]]
function PgInfo:initialize(host, port, user, pwd, database, source)
	self.connection_string = string.format("host=%s port=%s dbname=%s user=%s password=%s", host, port, database, user, pwd)
	--p(string.format("connection string: %s", self.connection_string))
	self.lock_modes = {'AccessExclusive', 'Exclusive', 'ShareRowExclusive', 'Share', 'ShareUpdateExclusive', 'RowExclusive', 'RowShare', 'AccessShare'}
	self.connection = nil
	return self
end

--[[ Establishing method required to be used before every query
]]
function PgInfo:establish(queries_callback)
	self.connection = postgresLuvit:new(self.connection_string, function(err)
		assert(not err, err)
		callIfNotNil(queries_callback, self.connection)
	end)
end

--[[ Test function
]]
function PgInfo:test(connection, callback)
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
						callIfNotNil(callback)
					end)
				end)
			end)
		end)
end

--[[ Get list of databases
]]
function PgInfo:get_databases(connection, callback)
		connection:sendQuery("SELECT datname FROM pg_database;",function(err, res)
			assert(not err, err)
			local dbs = res
			
			callIfNotNil(callback, dbs)
		end)
end


--[[ Returns the number of active lock discriminated by lock mode
]]
function PgInfo:get_lock_stats_mode(connection, callback)
		connection:sendQuery("SELECT TRIM(mode, 'Lock'), granted, COUNT(*) FROM pg_locks " .. "GROUP BY TRIM(mode, 'Lock'), granted;", function(err, res)
			assert(not err, err)
			info_dict = { wait = createDictWithKeys(self.lock_modes, 0), all = createDictWithKeys(self.lock_modes, 0)}
			
			for i, value in ipairs(res) do
				local mode = value[1]
				local granted = value[2] == "t"
				local count = value[3]
				
				info_dict['all'][mode] = info_dict['all'][mode] + count
				if not granted then
					info_dict['wait'][mode] = info_dict['wait'][mode] + count
				end
			end
	
			callIfNotNil(callback, info_dict)
		end)
end


--[[ Global Background Writer and Checkpoint Activity stats
]]
function PgInfo:get_bg_writer_stats(connection, callback)
		connection:sendQuery("SELECT * FROM pg_stat_bgwriter;", function(err, res)
			assert(not err, err)
			info_dict = {}
			
			for i=1, table.getn(res[0]) do
				local name = res[0][i]
				local result = res[1][i]
				info_dict[name] = result
			end
			
			callIfNotNil(callback, info_dict)
		end)
end

--[[ Returns database block read, transaction and tuple stats for each 
        database
]]
function PgInfo:get_database_stats(connection, callback)
	local headers = {'datname', 'numbackends', 'xact_commit', 'xact_rollback', 
			   'blks_read', 'blks_hit', 'tup_returned', 'tup_fetched', 
			   'tup_inserted', 'tup_updated', 'tup_deleted', 'disk_size'}
	local query_headers = deepcopy(headers)
	table.remove(query_headers, table.getn(query_headers))
	
	local query_string = string.format("SELECT %s, pg_database_size(datname) FROM pg_stat_database;", table.concat(query_headers, ", "))
	connection:sendQuery(query_string, function(err, res)
		assert(not err, err)
		info_dict = {}
		info_dict['databases'] = self:create_stats_dict(headers, res)
		info_dict['totals'] = self:create_totals_dict(headers, res)
		
		callIfNotNil(callback, info_dict)
	end)
end


--[[ Utility method that returns database stats as a nested dictionary
]]
function PgInfo:create_stats_dict(headers, rows)
	local db_stats = {}
	table.remove(headers, 1)
	for index, row in ipairs(rows) do
		local key = row[1]
		table.remove(row, 1)
		local stats = createDictWithKeysAndValues(headers, row)
		db_stats[key] = stats
	end
	return db_stats
end


--[[ Utility method that returns totals for database statistics
]]
function PgInfo:create_totals_dict(headers, rows)
	local totals_dict = {}
	local totals = {}	
	for key,row in ipairs(rows) do
		local key = row[1]
		
		for i=1, table.getn(row) do
			if totals[i] ~= nil then
				totals[i] = totals[i] + row[i]
			else
				totals[i] = row[i]
			end
		end
	end

	for index, header in ipairs(headers) do
		totals_dict[header] = totals[index]
	end
	return totals_dict
end

return PgInfo