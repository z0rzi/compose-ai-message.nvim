local M = {
}

M.config = {
  file = '/tmp/.ai-message.md',

  mappings = {
    reset = '<leader>mr',
    open_file = '<leader>mo',
    add_visual_selection = '<leader>ma',
    add_full_buffer = '<leader>ma',
  },
}

-- Utility: Write (overwrite) file
local function write_file(filename, contents)
  local file, err = io.open(filename, "w")
  if not file then
    vim.notify("Failed to open file: " .. err, vim.log.levels.ERROR)
    return false
  end
  file:write(contents or "")
  file:close()
  return true
end

-- Utility: Append to file
local function append_file(filename, contents)
  local file, err = io.open(filename, "a")
  if not file then
    vim.notify("Failed to open file: " .. err, vim.log.levels.ERROR)
    return false
  end
  file:write(contents)
  file:close()
  return true
end

-- Get buffer path relative to cwd
local function relativename(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.loop.cwd()
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 2)
    if path == "" then path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") end
  end
  return path ~= "" and path or "[No Name]"
end

-- Resets (empties) the file
function M.reset()
  write_file(M.config.file, "")
  vim.notify("AI message file reset.")
end

-- Add code block entry given lines, lang, user_message
local function add_entry(user_message, relative_path, lang, lines)
  local entry = user_message .. "\n"
    .. "(" .. relative_path .. ")\n"
    .. "```" .. (lang or "") .. "\n"
    .. table.concat(lines, "\n") .. "\n"
    .. "```\n\n"
  local ok = append_file(M.config.file, entry)
  if ok then
    vim.notify("Selection added to AI message file.")
  end
end

-- Prompt user for input (blocking)
local function prompt_user(msg, cb)
  vim.ui.input({ prompt = msg }, function(input)
    if not input then
      vim.notify("Aborted (no message entered).", vim.log.levels.WARN)
    else
      cb(input)
    end
  end)
end

-- Get visual selection lines (inclusive), returns lines, buffer-relative line numbers
local function get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.mode()

  -- Get range start/end
  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_pos   = vim.api.nvim_buf_get_mark(bufnr, ">")

  local start_line = start_pos[1]
  local end_line   = end_pos[1]

  -- nvim indices: start/end lines are inclusive, 1-based
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return lines, start_line, end_line
end

-- Add visual selection to AI message file
function M.add_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype or ""
  local relname = relativename(bufnr)
  local lines = select(1, get_visual_selection())
  -- Prompt for user message, then append
  prompt_user("Describe the visual selection:", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

-- Add full buffer to AI message file
function M.add_full_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype or ""
  local relname = relativename(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  prompt_user("Describe the full buffer:", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

-- Opens the message file in the current window, editing it
function M.open_file()
  vim.cmd("edit " .. vim.fn.fnameescape(M.config.file))
end

function M.setup_mappings()
  local opts = { noremap = true, silent = true }

  -- Visual selection mapping (visual mode)
  vim.api.nvim_set_keymap("x",
    M.config.mappings.add_visual_selection,
    "<Esc><Cmd>lua require('compose-ai-message').add_visual_selection()<CR>",
    opts)

  -- Full buffer mapping (normal mode)
  vim.api.nvim_set_keymap("n",
    M.config.mappings.add_full_buffer,
    "<Cmd>lua require('compose-ai-message').add_full_buffer()<CR>",
    opts)

  -- Reset mapping (normal mode)
  vim.api.nvim_set_keymap("n",
    M.config.mappings.reset,
    "<Cmd>lua require('compose-ai-message').reset()<CR>",
    opts)

  -- Open file mapping (normal mode)
  vim.api.nvim_set_keymap("n",
    M.config.mappings.open_file,
    "<Cmd>lua require('compose-ai-message').open_file()<CR>",
    opts)
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()

  -- Reset the file at startup
  M.reset()
end

return M
