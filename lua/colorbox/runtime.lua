local uv = require("colorbox.commons.uv")
local fileios = require("colorbox.commons.fileios")
local tables = require("colorbox.commons.tables")
local logging = require("colorbox.commons.logging")
local strings = require("colorbox.commons.strings")
local msgpack = require("colorbox.commons.msgpack")

local configs = require("colorbox.configs")
local filter = require("colorbox.filter")

local M = {}

-- filtered color names list
--- @type string[]
local FilteredColorNamesList = {}

-- the reverse of FilteredColorNamesList (index => name)
--- @type table<string, integer>
local FilteredColorNameToIndexMap = {}

--- @return {colors_list:string[],colors_index:table<string,integer>}
M._build_colors = function()
  local colors_list = {}
  local colors_index = {}

  local ColorNameToColorSpecsMap = require("colorbox.db").get_color_name_to_color_specs_map()
  local ColorNamesList = require("colorbox.db").get_color_names_list()
  for _, color_name in pairs(ColorNamesList) do
    local spec = ColorNameToColorSpecsMap[color_name]
    local pack_exist = uv.fs_stat(spec.full_pack_path) ~= nil
    if filter.run(color_name, spec) and pack_exist then
      table.insert(colors_list, color_name)
    end
  end
  for i, color_name in ipairs(colors_list) do
    colors_index[color_name] = i
  end

  return {
    colors_list = colors_list,
    colors_index = colors_index,
  }
end

M.setup = function()
  local logger = logging.get("colorbox") --[[@as commons.logging.Logger]]

  local home_dir = vim.fn["colorbox#base_dir"]()
  vim.opt.packpath:append(home_dir)

  local confs = configs.get()
  logger:debug("|setup| confs.previous_colors_cache:%s", vim.inspect(confs.previous_colors_cache))
  local cache_content = fileios.readfile(confs.previous_colors_cache, { trim = true })
  logger:debug("|setup| cache_content:%s", vim.inspect(cache_content))
  local found_cache = false

  if cache_content then
    local cache_data = msgpack.unpack(cache_content) --[[@as table]]
    logger:debug("|setup| cache_data:%s", vim.inspect(cache_data))
    if
      tables.list_not_empty(tables.tbl_get(cache_data, "colors_list"))
      and tables.tbl_not_empty(tables.tbl_get(cache_data, "colors_index"))
    then
      FilteredColorNamesList = cache_data.colors_list
      FilteredColorNameToIndexMap = cache_data.colors_index
      found_cache = true

      vim.defer_fn(function()
        local data = M._build_colors()
        fileios.asyncwritefile(
          confs.previous_colors_cache,
          msgpack.pack(data) --[[@as string]],
          function()
            logger:debug("|setup| found cache, update cache - done")
          end
        )
      end, 100)
    end
  end

  if not found_cache then
    local data = M._build_colors()
    logger:debug("|setup| not found, data:%s", vim.inspect(data))
    FilteredColorNamesList = data.colors_list
    FilteredColorNameToIndexMap = data.colors_index

    vim.defer_fn(function()
      fileios.asyncwritefile(
        confs.previous_colors_cache,
        msgpack.pack(data) --[[@as string]],
        function()
          logger:debug("|setup| not found cache, dump cache - done")
        end
      )
    end, 100)
  end

  -- logger:debug("|_init| FilteredColorNamesList:%s", vim.inspect(FilteredColorNamesList))
  -- logger:debug("|_init| FilteredColorNameToIndexMap:%s", vim.inspect(FilteredColorNameToIndexMap))
end

M.colornames = function()
  return FilteredColorNamesList
end

M.colornames_index = function()
  return FilteredColorNameToIndexMap
end

return M
