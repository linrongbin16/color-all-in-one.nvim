local num = require("colorbox.commons.num")
local str = require("colorbox.commons.str")
local logging = require("colorbox.commons.logging")
local LogLevels = require("colorbox.commons.logging").LogLevels
local async = require("colorbox.commons.async")
local spawn = require("colorbox.commons.spawn")

local loader = require("colorbox.loader")

local runtime = require("colorbox.runtime")
local db = require("colorbox.db")

local M = {}

M.update = function()
  if not logging.has("colorbox-update") then
    logging.setup({
      name = "colorbox-update",
      level = LogLevels.DEBUG,
      console_log = true,
      file_log = true,
      file_log_name = "colorbox_update.log",
      file_log_mode = "w",
    })
  end
  local logger = logging.get("colorbox-update")

  local home_dir = vim.fn["colorbox#base_dir"]()
  local packstart = string.format("%s/pack/colorbox/start", home_dir)
  logger:debug(
    string.format(
      "|colorbox.init| home_dir:%s, packstart:%s",
      vim.inspect(home_dir),
      vim.inspect(packstart)
    )
  )
  vim.opt.packpath:append(home_dir)

  local HandleToColorSpecsMap = db.get_handle_to_color_specs_map()

  local prepared_count = 0
  for _, _ in pairs(HandleToColorSpecsMap) do
    prepared_count = prepared_count + 1
  end
  logger:info(string.format("started %s jobs", vim.inspect(prepared_count)))

  local async_run = async.wrap(function(cmd, opts, cb)
    spawn.detached(cmd, opts, function(result)
      cb(result)
    end)
  end, 3)

  async.void(function()
    local finished_count = 0

    for handle, spec in pairs(HandleToColorSpecsMap) do
      local function _on_output(line)
        if str.not_blank(line) then
          logger:info(string.format("%s: %s", handle, line))
        end
      end
      local pack_path = db.get_pack_path(spec)
      local full_pack_path = db.get_full_pack_path(spec)
      local param = nil
      if
        vim.fn.isdirectory(full_pack_path) > 0
        and vim.fn.isdirectory(full_pack_path .. "/.git") > 0
      then
        param = {
          cmd = { "git", "pull" },
          opts = {
            cwd = full_pack_path,
            on_stdout = _on_output,
            on_stderr = _on_output,
          },
        }
        -- logger:debug(
        --   string.format(
        --     "|_update| git pull param:%s, spec:%s",
        --     vim.inspect(param),
        --     vim.inspect(spec)
        --   )
        -- )
      else
        param = {
          cmd = str.not_empty(spec.git_branch) and {
            "git",
            "clone",
            "--branch",
            spec.git_branch,
            "--depth=1",
            spec.url,
            pack_path,
          } or {
            "git",
            "clone",
            "--depth=1",
            spec.url,
            pack_path,
          },
          opts = {
            cwd = home_dir,
            on_stdout = _on_output,
            on_stderr = _on_output,
          },
        }
        -- logger:debug(
        --   string.format(
        --     "|_update| git clone param:%s, spec:%s",
        --     vim.inspect(param),
        --     vim.inspect(spec)
        --   )
        -- )
      end
      async_run(param.cmd, param.opts)
      async.schedule()
      finished_count = finished_count + 1
    end

    logger:info(string.format("finished %s jobs", vim.inspect(finished_count)))
  end)()
end

--- @param args string?
--- @return colorbox.Options?
M._parse_args = function(args)
  local opts = nil
  logging.get("colorbox"):debug(string.format("|_parse_args| args:%s", vim.inspect(args)))
  if str.not_blank(args) then
    local args_splits = str.split(vim.trim(args --[[@as string]]), " ", { trimempty = true })
    for _, arg_split in ipairs(args_splits) do
      local item_splits = str.split(vim.trim(arg_split), "=", { trimempty = true })
      if str.not_blank(item_splits[1]) then
        if opts == nil then
          opts = {}
        end
        opts[vim.trim(item_splits[1])] = vim.trim(item_splits[2] or "")
      end
    end
  end
  return opts
end

M.shuffle = function()
  local ColorNamesList = runtime.colornames()
  if #ColorNamesList > 0 then
    local logger = logging.get("colorbox")
    local random_index = num.random(1, #ColorNamesList)
    local color = ColorNamesList[random_index]

    logger:debug(
      string.format(
        "|shuffle| color:%s, random_index:%d, ColorNamesList(%d):%s",
        vim.inspect(color),
        random_index,
        #ColorNamesList,
        vim.inspect(ColorNamesList)
      )
    )
    loader.load(color)
  end
end

--- @param args string?
M.info = function(args)
  local logger = logging.get("colorbox")
  local opts = M._parse_args(args)
  opts = opts or { scale = 0.7 }
  opts.scale = type(opts.scale) == "string" and (tonumber(opts.scale) or 0.7) or 0.7
  opts.scale = num.bound(opts.scale, 0, 1)
  logging.get("colorbox"):debug(string.format("|_info| opts:%s", vim.inspect(opts)))

  local total_width = vim.o.columns
  local total_height = vim.o.lines
  local width = math.floor(total_width * opts.scale)
  local height = math.floor(total_height * opts.scale)

  local function get_shift(totalsize, modalsize, offset)
    local base = math.floor((totalsize - modalsize) * 0.5)
    local shift = offset > -1 and math.ceil((totalsize - modalsize) * offset) or offset
    return num.bound(base + shift, 0, totalsize - modalsize)
  end

  local row = get_shift(total_height, height, 0)
  local col = get_shift(total_width, width, 0)

  local win_config = {
    anchor = "NW",
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 51,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  vim.keymap.set({ "n" }, "q", ":\\<C-U>quit<CR>", { silent = true, buffer = bufnr })
  local winnr = vim.api.nvim_open_win(bufnr, true, win_config)

  local ColorNamesIndex = runtime.colornames_index()
  local HandleToColorSpecsMap = require("colorbox.db").get_handle_to_color_specs_map()
  local color_specs_list = {}
  for handle, spec in pairs(HandleToColorSpecsMap) do
    table.insert(color_specs_list, spec)
  end
  table.sort(color_specs_list, function(a, b)
    return a.github_stars > b.github_stars
  end)
  local total_plugins = 0
  local total_colors = 0
  local enabled_plugins = 0
  local enabled_colors = 0
  for i, spec in ipairs(color_specs_list) do
    total_plugins = total_plugins + 1
    local plugin_enabled = false
    for j, color in ipairs(spec.color_names) do
      total_colors = total_colors + 1
      local color_enabled = ColorNamesIndex[color] ~= nil
      if color_enabled then
        enabled_colors = enabled_colors + 1
        plugin_enabled = true
      end
    end
    if plugin_enabled then
      enabled_plugins = enabled_plugins + 1
    end
  end

  local ns = vim.api.nvim_create_namespace("colorbox-info-panel")
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, true, {
    string.format(
      "# ColorSchemes List, total: %d(colors)/%d(plugins), enabled: %d(colors)/%d(plugins)",
      total_colors,
      total_plugins,
      enabled_colors,
      enabled_plugins
    ),
  })
  local lineno = 1
  for i, spec in ipairs(color_specs_list) do
    vim.api.nvim_buf_set_lines(bufnr, lineno, lineno, true, {
      string.format(
        "- %s (stars: %s, last update at: %s)",
        vim.inspect(spec.handle),
        vim.inspect(spec.github_stars),
        vim.inspect(spec.last_git_commit)
      ),
    })
    lineno = lineno + 1
    local color_names = vim.deepcopy(spec.color_names)
    -- table.sort(color_names, function(a, b)
    --   logger:debug(
    --     string.format(
    --       "|info| sort color_names:%s, ColorNamesIndex:%s",
    --       vim.inspect(color_names),
    --       vim.inspect(ColorNamesIndex)
    --     )
    --   )
    --   local a_enabled = ColorNamesIndex[a] ~= nil
    --   return a_enabled
    -- end)

    for _, color in ipairs(color_names) do
      local enabled = ColorNamesIndex[color] ~= nil
      local content = enabled and string.format("  - %s (**enabled**)", color)
        or string.format("  - %s (disabled)", color)
      vim.api.nvim_buf_set_lines(bufnr, lineno, lineno, true, { content })

      -- colorize the enabled colors
      if enabled then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lineno, 0, {
          end_row = lineno,
          end_col = string.len(content),
          strict = false,
          line_hl_group = "Special",
        })
      end
      lineno = lineno + 1
    end
  end
  vim.schedule(function()
    vim.cmd(string.format([[call setpos('.', [%d, 1, 1])]], bufnr))
  end)
end

return M
