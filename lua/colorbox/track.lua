local str = require("colorbox.commons.str")
local num = require("colorbox.commons.num")
local fio = require("colorbox.commons.fio")
local logging = require("colorbox.commons.logging")

local configs = require("colorbox.configs")
local runtime = require("colorbox.runtime")
local db = require("colorbox.db")

local M = {}

M.sync_syntax = function()
  vim.schedule(function()
    vim.cmd([[syntax sync fromstart]])
  end)
end

--- @alias colorbox.PreviousTrack {color_name:string,color_number:integer}
--- @param color_name string
M.save_track = function(color_name)
  local logger = logging.get("colorbox")
  if str.blank(color_name) then
    logger:debug(string.format("|save_track| color_name is blank:%s", vim.inspect(color_name)))
    return
  end

  vim.schedule(function()
    local confs = configs.get()

    local ColorNamesIndex = runtime.colornames_index()
    local color_number = ColorNamesIndex[color_name] or 1

    local content = vim.json.encode({
      color_name = color_name,
      color_number = color_number,
    }) --[[@as string]]

    fio.asyncwritefile(confs.previous_track_cache, content, function()
      logger:debug(
        string.format(
          "|save_track| finished save track for color_name:%s, color_number:%s",
          vim.inspect(color_name),
          vim.inspect(color_number)
        )
      )
      vim.schedule(function()
        if vim.is_callable(confs.post_hook) then
          local ColorNameToColorSpecsMap = db.get_color_name_to_color_specs_map()
          local color_spec = ColorNameToColorSpecsMap[color_name]
          confs.post_hook(color_name, color_spec)
        end
      end)
    end)
  end)
end

--- @return colorbox.PreviousTrack?
M.previous_track = function()
  local confs = configs.get()
  local content = fio.readfile(confs.previous_track_cache)
  if str.empty(content) then
    return nil
  end
  return vim.json.decode(content) --[[@as colorbox.PreviousTrack?]]
end

--- @param idx integer
--- @return string, integer
M.get_next_color_name_by_idx = function(idx)
  assert(type(idx) == "number")
  idx = idx + 1
  local ColorNamesList = runtime.colornames()
  local n = #ColorNamesList
  if idx > n then
    idx = 1
  end
  idx = num.bound(idx, 1, n)
  return ColorNamesList[idx], idx
end

--- @param idx integer
--- @return string, integer
M.get_prev_color_name_by_idx = function(idx)
  assert(type(idx) == "number")
  idx = idx - 1
  local ColorNamesList = runtime.colornames()
  local n = #ColorNamesList
  if idx < 1 then
    idx = n
  end
  idx = num.bound(idx, 1, n)
  return ColorNamesList[idx], idx
end

return M
