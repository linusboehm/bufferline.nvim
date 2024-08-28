local lazy = require("bufferline.lazy")
local utils = lazy.require("bufferline.utils") ---@module "bufferline.utils"
local autocmds = lazy.require("bufferline.manage_buffers_autocmds") ---@module "bufferline.manage_buffers_autocmds"

local M = {}

local fmt = string.format

---@param bufnr number
local function get_contents(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local indices = {}

    for _, line in pairs(lines) do
        table.insert(indices, line)
    end

    return indices
end

---@class bufferline.BuffersUi
local BuffersUi = {}

BuffersUi.__index = BuffersUi

---@return bufferline.BuffersUi
function BuffersUi:new()
    utils.notify(fmt("creating a new buffer"), "debug")
    return setmetatable({
        win_id = nil,
        bufnr = nil,
    }, self)
end

function BuffersUi:close_menu()
    if self.closing then
        return {}
    end
    local files = get_contents(self.bufnr)

    self.closing = true
    if self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end

    if self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end

    self.win_id = nil
    self.bufnr = nil

    self.closing = false
    return files
end

function BuffersUi:_create_window()
    local win = vim.api.nvim_list_uis()

    local width = 20

    if #win > 0 then
        width = math.floor(win[1].width * .5)
    end

    local height = 20
    local bufnr = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        title = "Manage Buffers",
        title_pos = "left",
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "single",
    })

    if win_id == 0 then
        self.bufnr = bufnr
        self:close_menu()
    end

    autocmds.setup_autocmds_and_keymaps(bufnr)

    self.win_id = win_id
    vim.api.nvim_set_option_value("number", true, {
        win = win_id,
    })

    return win_id, bufnr
end

local function path_formatter(path)
  return vim.fn.fnamemodify(path, ":p:.")
end

--- @param elements bufferline.TabElement[]
function BuffersUi:open_quick_menu(elements)
    local win_id, bufnr = self:_create_window()

    self.win_id = win_id
    self.bufnr = bufnr

    local contents = {}

    for index, buf in ipairs(elements) do
      contents[index] = path_formatter(buf.path)
    end

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, contents)
end

local function get_file_path()
    local filename = (vim.fn.getcwd() .. "_buffer_manager.json"):gsub("/", "_")
    local nvim_state_dir = vim.fn.stdpath('state')
    return nvim_state_dir .. "/sessions/" .. filename
end

local function read_json_file()
    local filepath = get_file_path()
    -- Open the file in read mode
    local file = io.open(filepath, "r")
    if not file then
        error("Could not open file: " .. filepath)
        return nil
    end

    -- Read the entire file content
    local content = file:read("*a")
    file:close()

    -- Decode the JSON content into a Lua table
    local decoded_content = vim.fn.json_decode(content)
    return decoded_content
end

local function update_bufferline(elements, buf_mngr_files)

    local commands = lazy.require("bufferline.commands")

    if next(buf_mngr_files) == nil then
      return
    end

    -- Create a lookup table path -> index
    local buffer_path_to_idx = {}
    for index, buf in ipairs(elements) do
        buffer_path_to_idx[path_formatter(buf.path)] = index
    end

    -- remove invalid entries from buf_mngr_files
    local filtered_buf_mngr_files = {}
    for _, name in ipairs(buf_mngr_files) do
        if buffer_path_to_idx[name] then
            table.insert(filtered_buf_mngr_files, name)
        end
    end

    -- Create a lookup table buf mngr file -> index
    local bm_file_to_idx = {}
    for index, name in ipairs(filtered_buf_mngr_files) do
        bm_file_to_idx[name] = index
    end


    -- remove deleted elements
    for _, item in ipairs(elements) do
      if not bm_file_to_idx[path_formatter(item.path)] then
          commands.unpin_and_close(item.id)
      end
    end

    vim.print("dumped to file: " .. get_file_path())
    local file = io.open(get_file_path(), "w")
    local json = vim.fn.json_encode(bm_file_to_idx)
    file:write(json)
    file:close()

    -- Custom sort function that uses the lookup table
    local function mysort(a, b)
        local mapping = read_json_file()
        if mapping == nil then
            vim.print("Error reading json file")
            return false
        end
        if mapping[path_formatter(a.path)] == nil or mapping[path_formatter(b.path)] == nil then return false end
        return mapping[path_formatter(a.path)] < mapping[path_formatter(b.path)]
    end
    commands.sort_by(mysort)
end

--- @param elements bufferline.TabElement[]
function M.toggle_buf_mngr(elements, buf_mngr)
    if buf_mngr.win_id ~= nil then
        local buf_mngr_files = buf_mngr:close_menu()
        update_bufferline(elements, buf_mngr_files)
    else
      buf_mngr:open_quick_menu(elements)
    end
end

M.BuffersUi = BuffersUi:new()

return M
