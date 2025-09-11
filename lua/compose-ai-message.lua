local M = {
}

local has_plenary, plenary_curl = pcall(require, "plenary.curl")

local OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")

M.config = {
  mappings = {
    reset = '<leader>mr',
    open_file = '<leader>mo',
    add_message = '<leader>mm',
    add_file_paths = '<leader>m.',
    add_visual_selection = '<leader>ma',
    add_full_buffer = '<leader>ma',
    copy_file = '<leader>my',
  },
}

local function get_md_file_path()
  -- The md file path is: /tmp/.{VIM_PID}-ai-message.md
  local pid = vim.fn.getpid()
  return "/tmp/" .. pid .. "-ai-message.md"
end

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

local function read_file(filename)
  local file, err = io.open(filename, "r")
  if not file then
    return nil, err
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function relativename(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.loop.cwd()
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 2)
    if path == "" then path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") end
  end
  return path ~= "" and path or "[No Name]"
end

function M.reset()
  write_file(get_md_file_path(), "")
  vim.notify("AI message file reset.")
end

local function add_entry(user_message, relative_path, lang, lines)
  local entry = user_message .. "\n"
    .. "(" .. relative_path .. ")\n"
    .. "```" .. (lang or "") .. "\n"
    .. table.concat(lines, "\n") .. "\n"
    .. "```\n\n"
  local ok = append_file(get_md_file_path(), entry)
  if ok then
    vim.notify("Selection added to AI message file.")
  end
end

local function prompt_user(msg, cb)
  vim.ui.input({ prompt = msg }, function(input)
    if not input then
      vim.notify("Aborted (no message entered).", vim.log.levels.WARN)
    else
      cb(input)
    end
  end)
end

local function get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.mode()
  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_pos   = vim.api.nvim_buf_get_mark(bufnr, ">")
  local start_line = start_pos[1]
  local end_line   = end_pos[1]
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return lines, start_line, end_line
end

function M.add_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype or ""
  local relname = relativename(bufnr)
  local lines = select(1, get_visual_selection())
  prompt_user("Describe the visual selection: ", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

function M.add_message()
  local relname = relativename(bufnr)
  prompt_user("Message : ", function(user_message)
    local entry = "(" .. relative_path .. ")\n" .. user_message

    local ok = append_file(get_md_file_path(), entry)
    if ok then
      vim.notify("Selection added to AI message file.")
    end
  end)
end

function M.add_file_paths()
  -- Adds all the file paths of all open buffers to the AI message file
  local bufnrs = vim.api.nvim_list_bufs()
  local entries = {}
  for _, bufnr in ipairs(bufnrs) do
    -- Checking if the buffer is a regular file
    local listed = vim.api.nvim_get_option_value('buflisted', { buf = bufnr })
    local path = relativename(bufnr)
    if listed and path ~= "" then
      table.insert(entries, '- ' .. path)
    end
  end
  local entry = 'Here are the files I\'m working on:\n'
    .. table.concat(entries, "\n")

  local ok = append_file(get_md_file_path(), entry)
  if ok then
    vim.notify("File paths added to AI message file.")
  end
end

function M.add_full_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype or ""
  local relname = relativename(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  prompt_user("Describe the full buffer: ", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

function M.open_file()
  vim.cmd("vs " .. vim.fn.fnameescape(get_md_file_path()) .. " | wincmd L")
end

local function get_ai_system_prompt()
  return "You are a helpful AI assistant. Respond to the user query concisely and informatively."
end

-- Copy the entire content of the md file to clipboard (system '+')
function M.copy_file_contents()
  local content, err = read_file(get_md_file_path())
  if not content then
    vim.notify("Failed to read file: " .. (err or ""), vim.log.levels.ERROR)
    return
  end
  if content == "" then
    vim.fn.setreg("+", "")
    vim.notify("AI message file is empty, copied empty string.", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg("+", content)
  vim.notify("AI message file copied to clipboard.")
end

function M.setup_mappings()
  local opts = { noremap = true, silent = true }

  vim.api.nvim_set_keymap("x",
    M.config.mappings.add_visual_selection,
    "<Esc><Cmd>lua require('compose-ai-message').add_visual_selection()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.add_message,
    "<Esc><Cmd>lua require('compose-ai-message').add_message()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.add_file_paths,
    "<Esc><Cmd>lua require('compose-ai-message').add_file_paths()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.add_full_buffer,
    "<Cmd>lua require('compose-ai-message').add_full_buffer()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.reset,
    "<Cmd>lua require('compose-ai-message').reset()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.open_file,
    "<Cmd>lua require('compose-ai-message').open_file()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.copy_file,
    "<Cmd>lua require('compose-ai-message').copy_file_contents()<CR>",
    opts)
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()

  M.reset()
end

return M
