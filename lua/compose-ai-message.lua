local M = {
}

local has_plenary, plenary_curl = pcall(require, "plenary.curl")

local OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")

M.config = {
  mappings = {
    reset = '<leader>mr',
    open_file = '<leader>mo',
    add_visual_selection = '<leader>ma',
    add_full_buffer = '<leader>ma',
    send_to_ai = "<leader>ms",
    replace_by_ai = "<leader>mx",
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
  prompt_user("Describe the visual selection:", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

function M.add_full_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype or ""
  local relname = relativename(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  prompt_user("Describe the full buffer:", function(user_message)
    add_entry(user_message, relname, lang, lines)
  end)
end

function M.open_file()
  vim.cmd("vs " .. vim.fn.fnameescape(get_md_file_path()) .. " | wincmd L")
end

local function get_ai_system_prompt()
  return "You are a helpful AI assistant. Respond to the user query concisely and informatively."
end

function M.send_to_ai()
  if not OPENROUTER_API_KEY then
    vim.notify("OPENROUTER_API_KEY environment variable is not set.", vim.log.levels.ERROR)
    return
  end

  -- Step 1: Read file content
  local content, err = read_file(get_md_file_path())
  if not content or content == "" then
    vim.notify("AI message file is empty or unreadable.", vim.log.levels.WARN)
    return
  end

  -- Step 2: Prepare payload
  local payload = {
    model = "openai/chatgpt-4o-latest",
    messages = {
      {
        role = "system",
        content = get_ai_system_prompt(),
      },
      {
        role = "user",
        content = content,
      }
    }
  }

  local json_payload = vim.fn.json_encode(payload)

  -- Step 3: Synchronous HTTP request using curl
  local endpoint = "https://openrouter.ai/api/v1/chat/completions"
  local curl_args = {
    "curl", "-sSL", "-X", "POST",
    "-H", "Authorization: Bearer " .. OPENROUTER_API_KEY,
    "-H", "Content-Type: application/json",
    "--data-binary", json_payload,
    endpoint
  }

  local response = vim.fn.system(curl_args)
  if vim.v.shell_error ~= 0 then
    vim.notify("Error talking to AI: " .. response, vim.log.levels.ERROR)
    return
  end

  -- Step 4: Parse JSON response (main thread, no callbacks)
  local ok, res = pcall(vim.fn.json_decode, response)
  if not ok then
    vim.notify("Failed to parse AI response: " .. tostring(response), vim.log.levels.ERROR)
    return
  end
  if not res or not res.choices or not res.choices[1] or not res.choices[1].message or not res.choices[1].message.content then
    vim.notify("No content in AI response.", vim.log.levels.ERROR)
    return
  end

  -- Step 5: Show output
  local ai_content = res.choices[1].message.content
  -- Truncate if more than 40 lines
  local lines = {}
  for line in ai_content:gmatch("([^\n]*)\n?") do table.insert(lines, line) end
  if #lines > 40 then
    ai_content = table.concat(vim.list_slice(lines, 1, 40), "\n") .. "\n... (output truncated)"
  end

  vim.notify(ai_content)
end

-- Helper: Prompt templates
local function get_plan_system_prompt()
  return "You are an expert code assistant. Your task is to *plan* updates to the provided code file(s) based on user instructions. DO NOT generate *any* code! Instead, create a step-by-step, detailed plan of the changes required to fulfill the user's intent, and explain your reasoning. No code output, just a precise and ordered plan."
end

local function get_codegen_system_prompt()
  return "You are an expert code rewriting assistant."
end

local CODE_BLOCK_SPEC = [[
# CODE BLOCK SPECIFICATION

CODE BLOCK TYPES: 
  - add
  - remove
  - replace

GENERAL STRUCTURE:
  Each code block begins with a triple-backtick and the operation type (`add`, `remove`, or `replace`) as the "language" label.
  All delimiters are exact and uppercase, surrounded by "== ", e.g. "== FILE ==".

FIELDS (all required unless otherwise specified):

=== COMMON FIELDS ===
== FILE ==
  Absolute or relative path to the file to be modified.

=== ADD BLOCK ===
Syntax: 
  ```add
  == FILE ==
  <file path>

  == ANCHOR ==
  <anchor text>    # This is an exact text match in the file

  == POSITION ==
  above | below    # Insert above or below the anchor.

  == TEXT ==
  <text to insert>
  ```
Requirements:
- The anchor must match exactly once in the file. If multiple matches, the first occurrence is used.
- The inserted text is placed above or below the anchor line.
- No trailing or leading stray content outside of `==` sections.

=== REMOVE BLOCK ===
Syntax: 
  ```remove
  == FILE ==
  <file path>

  == FROM ==
  <starting text of range to remove>

  == TO ==
  <ending text of range to remove>
  ```
Requirements:
- Both FROM and TO are exact code snippets found in the file.
- The first occurrence of FROM marks the start of removal, the first occurrence of TO marks the end (inclusive).
- All content between (and including) FROM and TO is removed.
- FROM and TO occur in order in the file.
- For replacing one line, indicate the same line in both FROM and TO.

=== REPLACE BLOCK ===
Syntax: 
  ```replace
  == FILE ==
  <file path>

  == FROM ==
  <starting text of range to replace>

  == TO ==
  <ending text of range to replace>

  == REPLACE_WITH ==
  <the replacement text>
  ```
Requirements:
- FROM/TO are handled as in REMOVE.
- All content between (and including) FROM and TO is replaced with the content of REPLACE_WITH.
- For replacing one line, indicate the same line in both FROM and TO.

NOTES:
- Code blocks are separated by triple-backticks and start with operation type.
- Text in fields (such as == FILE == or == ANCHOR ==) must be exact and on its own line.
- All line breaks and spaces within == TEXT ==, == FROM ==, == TO ==, and == REPLACE_WITH == must be preserved exactly.
- The format is line-based and plain-text; no structured markup or encoding.

EXAMPLE - ADD:
```add
== FILE ==
/path/to/file.ts

== ANCHOR ==
import { foo } from 'bar';
import { baz } from 'qux';

== POSITION ==
below

== TEXT ==
import { bar }
```

EXAMPLE - REMOVE:
```remove
== FILE ==
/path/to/file.ts

== FROM ==
function helper() {
  // do stuff

== TO ==
  return true;
}
```

EXAMPLE - REPLACE:
```replace
== FILE ==
/path/to/file.ts

== FROM ==
let count = 0;
for (let i = 0; i < 10; i++) {

== TO ==
let max = 1;

== REPLACE_WITH ==
let counter = 10;
let maximum = 42;
```
]]

-- Step 1: Request AI plan (no code)
local function request_ai_plan(ai_content)
  local plenary_curl = require("plenary.curl")
  local endpoint = "https://openrouter.ai/api/v1/chat/completions"
  local system_prompt = get_plan_system_prompt()
  local payload = {
    model = "openai/chatgpt-4o-latest",
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = ai_content }
    }
  }
  local json_payload = vim.fn.json_encode(payload)
  local headers = {
    Authorization = "Bearer " .. (os.getenv("OPENROUTER_API_KEY") or ""),
    ["Content-Type"] = "application/json",
  }

  local response = plenary_curl.post(endpoint, {
    headers = headers,
    body = json_payload,
    timeout = 100000,
  })
  if not response or not response.status or response.status ~= 200 or not response.body then
    return nil, "Network/AI error: " .. (type(response) == "table" and response.body or tostring(response))
  end

  local ok, json = pcall(vim.fn.json_decode, response.body)
  if not ok or not json or not json.choices or not json.choices[1] or not json.choices[1].message then
    return nil, "Failed to decode AI plan response"
  end

  return json.choices[1].message.content, nil
end

-- Step 2: Request AI code blocks
local function request_ai_codeblocks(ai_content, plan)
  local plenary_curl = require("plenary.curl")
  local endpoint = "https://openrouter.ai/api/v1/chat/completions"
  local system_prompt = get_codegen_system_prompt()
  local instructions = "Based on the following user message and the below plan, generate the actual file modifications as CODE BLOCKS ONLY, using STRICTLY the format shown below in the CODE BLOCK SPECIFICATION. DO NOT write any explanation or prose -- your response must be one or more code blocks, as per the example. No markdown headers. Separate multiple modifications with separate code blocks."
  local user_message = table.concat({
    instructions,
    "",
    "-----",
    "USER'S MESSAGE CONTENT:",
    ai_content,
    "-----",
    "PLAN (do not rephrase):",
    plan,
    "-----",
    CODE_BLOCK_SPEC
  }, "\n")

  local payload = {
    model = "openai/chatgpt-4o-latest",
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = user_message }
    }
  }
  local json_payload = vim.fn.json_encode(payload)
  local headers = {
    Authorization = "Bearer " .. (os.getenv("OPENROUTER_API_KEY") or ""),
    ["Content-Type"] = "application/json",
  }

  local response = plenary_curl.post(endpoint, {
    headers = headers,
    body = json_payload,
    timeout = 100000,
  })
  if not response or not response.status or response.status ~= 200 or not response.body then
    return nil, "Network/AI error: " .. (type(response) == "table" and response.body or tostring(response))
  end

  local ok, json = pcall(vim.fn.json_decode, response.body)
  if not ok or not json or not json.choices or not json.choices[1] or not json.choices[1].message then
    return nil, "Failed to decode AI codeblock response"
  end

  return json.choices[1].message.content, nil
end

-- Step 3: Code block parsing
local function parse_code_blocks(text)
  -- Returns: { {type="add"/"remove"/"replace", raw=block_string}, ... }
  local blocks = {}
  -- Pattern: triple backtick, then type, then any chars until triple backtick again
  local blocktypes = {"add", "remove", "replace"}

  for k, blocktype in pairs(blocktypes) do
    for content in string.gmatch(text, "```"..blocktype.."(.-)```") do
      table.insert(blocks, {type=blocktype, raw=("```"..blocktype..content.."```")})
    end
  end
  print(vim.inspect(blocks))
  return blocks
end

-- Step 4: Parse block fields (all fields delimited by "== XXX ==" on line)
local function parse_block_fields(block_str)
  local blocktype = block_str:match("^```(%w+)")
  if not blocktype then return nil, "Missing block type" end
  local fields = {}
  -- Remove the ```blocktype and trailing ```
  -- We look for '== FIELD ==\n' (then capture everything up to the next '== ... ==' or end),
  -- using a loop.
  local inner = block_str:match("^```%w+\n(.-)```$") or ""
  local pos = 1
  while pos <= #inner do
    local s, e, field = inner:find("== ([%u_]+) ==\n", pos)
    if not s then break end
    local next_s, _, _ = inner:find("== [%u_]+ ==\n", e+1)
    local value
    if next_s then
      value = inner:sub(e + 1, next_s - 1)
      pos = next_s
    else
      value = inner:sub(e + 1)
      pos = #inner + 1
    end
    -- Trim only right-side line breaks
    value = value:gsub("[\r\n]+$", "")
    fields[field] = value
  end
  return blocktype, fields
end

local function with_relative_path(file_path)
  if vim.loop.fs_stat(file_path) then return file_path end
  -- try as relative to CWD
  local try = vim.loop.cwd() .. "/" .. file_path
  if vim.loop.fs_stat(try) then return try end
  return file_path -- fallback
end

-- Step 5: Code block application logic
local function split_lines(text)
  local t, n = {}, 0
  for line in tostring(text or ""):gmatch("([^\r\n]*)\r?\n?") do
    n = n + 1
    t[n] = line
  end
  -- Remove trailing blank lines
  while #t > 0 and t[#t]:match("^%s*$") do table.remove(t, #t) end
  while #t > 0 and t[1]:match("^%s*$") do table.remove(t, 1) end
  return t
end

local function lines_eq(a, b)
  if #a ~= #b then return false end
  for i=1,#a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function lines_preview(lines, startidx, stopidx)
  local out = {}
  for i=(startidx or 1),(stopidx or #lines) do
    out[#out+1] = string.format("%4d | %s", i, lines[i])
  end
  return table.concat(out, "\n")
end

-- Debug block finder
local function find_block_range_debug(lines, from_lines, to_lines)
  local N = #lines
  local F = #from_lines
  local T = #to_lines
  print(lines_preview(from_lines))
  print(lines_preview(to_lines))
  for i = 1, N - F + 1 do
    local match_from = true
    for k = 1, F do
      local l1 = lines[i + k - 1]
      local l2 = from_lines[k]
      if l1 ~= l2 then
        match_from = false
        break
      end
    end
    if match_from then
      print(("  Found FROM match starting at line %d"):format(i))
      -- Show what lines matched FROM
      print("  Matched lines (FROM):\n" .. lines_preview(lines, i, i+F-1))
      -- Now scan for TO
      for j = i, N - T + 1 do
        local match_to = true
        for k = 1, T do
          local l1 = lines[j + k - 1]
          local l2 = to_lines[k]
          if l1 ~= l2 then
            match_to = false
            break
          end
        end
        if match_to then
          print(("  Found TO match starting at line %d, ends at line %d"):format(j, j+T-1))
          print("  Matched lines (TO):\n" .. lines_preview(lines, j, j+T-1))
          return i, (j + T - 1)
        end
      end
    end
  end
  return nil, nil
end

local function find_anchor_range(lines, anchor_lines)
  -- Finds the start (inclusive) and end (inclusive) indices in lines that match anchor_lines sequence
  local N, M = #lines, #anchor_lines
  if M == 0 then return nil, nil end
  for i = 1, N - M + 1 do
    local found = true
    for j = 1, M do
      if lines[i + j - 1] ~= anchor_lines[j] then
        found = false
        break
      end
    end
    if found then
      return i, i + M - 1
    end
  end
  return nil, nil
end

local function apply_code_block(blocktype, fields)
  local file = fields["FILE"]
  if not file or file == "" then return false, "No file path specified." end
  local resolved = with_relative_path(file)
  local orig, read_err = read_file(resolved)
  if not orig then
    return false, "Could not open '" .. file .. "': " .. (read_err or "")
  end
  local changed = false
  local lines = split_lines(orig)
  local out = {}

  if blocktype == "add" then
    -- PATCHED: Handle multi-line anchor
    local anchor = fields["ANCHOR"]
    local pos = fields["POSITION"] and tostring(fields["POSITION"]):lower() or ""
    local text = fields["TEXT"] or ""
    if not anchor or anchor == "" then return false, "No anchor for add block" end
    if pos ~= "above" and pos ~= "below" then return false, "Invalid POSITION: " .. tostring(pos) end

    -- Trimming whitespaces from start and end of anchor
    anchor = anchor:gsub("^%s+", "")
    anchor = anchor:gsub("%s+$", "")
    local anchor_lines = split_lines(anchor)
    local a_start, a_end = find_anchor_range(lines, anchor_lines)
    if not a_start or not a_end then
      return false, ("Anchor (multi-line) not found in file: [%s]"):format(anchor)
    end

    for idx, line in ipairs(lines) do
      if idx == a_start then
        -- Insert above (if requested)
        if pos == "above" then
          local newlines = split_lines(text)
          for _, l in ipairs(newlines) do table.insert(out, l) end
          changed = true
        end
      end
      -- Output anchor lines
      if idx >= a_start and idx <= a_end then
        table.insert(out, line)
      elseif idx < a_start or idx > a_end then
        table.insert(out, line)
      end
      -- Insert below after last anchor line
      if idx == a_end then
        if pos == "below" then
          local newlines = split_lines(text)
          for _, l in ipairs(newlines) do table.insert(out, l) end
          changed = true
        end
      end
    end

  elseif blocktype == "remove" then
    local from_str = fields["FROM"] or ""
    local to_str = fields["TO"] or ""
    local from_lines = split_lines(from_str)
    local to_lines = split_lines(to_str)
    if #from_lines == 0 or #to_lines == 0 then
      return false, "No FROM/TO for remove block"
    end

    local s, e = find_block_range_debug(lines, from_lines, to_lines)
    if not s or not e or (s > e) then
      return false, "Could not find valid FROM/TO lines for remove block."
    end

    for i = 1, #lines do
      if i < s or i > e then
        table.insert(out, lines[i])
      else
        changed = true
      end
    end

  elseif blocktype == "replace" then
    local from_str = fields["FROM"] or ""
    local to_str = fields["TO"] or ""
    local rep_str = fields["REPLACE_WITH"] or ""
    local from_lines = split_lines(from_str)
    local to_lines = split_lines(to_str)
    local rep_lines = split_lines(rep_str)
    if #from_lines == 0 or #to_lines == 0 then
      return false, "No FROM/TO for replace block"
    end

    local s, e = find_block_range_debug(lines, from_lines, to_lines)
    if not s or not e or (s > e) then
      return false, "Could not find valid FROM/TO lines for replace block."
    end

    for i = 1, #lines do
      if i == s then
        for _, l in ipairs(rep_lines) do table.insert(out, l) end
        changed = true
      end
      if i < s or i > e then
        table.insert(out, lines[i])
      end
    end

  else
    return false, "Unknown blocktype: " .. tostring(blocktype)
  end

  if changed then
    write_file(resolved, table.concat(out, "\n") .. "\n")
  end

  return changed, nil
end

-- MAIN ENTRYPOINT
function M.replace_by_ai()
  local ai_file = get_md_file_path()
  local message_content, err = read_file(ai_file)
  if not message_content or message_content == "" then
    vim.notify("AI message file is empty or unreadable.", vim.log.levels.WARN)
    return
  end
  vim.notify("Step 1/3: Requesting AI plan...", vim.log.levels.INFO)
  vim.wait(100)
  local plan, err1 = request_ai_plan(message_content)
  if not plan then
    vim.notify("AI planning failed: " .. (err1 or ""), vim.log.levels.ERROR)
    return
  end
  -- optional: show plan for user confirmation, or skip
  -- for brevity: continue

  vim.notify("Step 2/3: Requesting generated code blocks from AI...", vim.log.levels.INFO)
  vim.wait(100)
  local blocks_raw, err2 = request_ai_codeblocks(message_content, plan)
  if not blocks_raw then
    vim.notify("AI codeblock generation failed: " .. (err2 or ""), vim.log.levels.ERROR)
    return
  end

  vim.notify("Step 3/3: Applying code blocks...", vim.log.levels.INFO)
  local blocks = parse_code_blocks(blocks_raw)
  if #blocks == 0 then
    vim.notify("No code blocks found in AI response.", vim.log.levels.ERROR)
    vim.notify(blocks_raw)
    return
  end

  local ok_count = 0
  local err_msgs = {}
  for _, block in ipairs(blocks) do
    local blocktype, fields = parse_block_fields(block.raw)
    if not blocktype or not fields then
      table.insert(err_msgs, "Failed to parse a code block.")
    else
      local changed, err = apply_code_block(blocktype, fields)
      if changed then
        ok_count = ok_count + 1
        vim.notify(("Patched file: %s (%s block applied)"):format(fields.FILE, blocktype), vim.log.levels.INFO)
      else
        table.insert(err_msgs, ("File %s: %s"):format(fields.FILE or "<?>", err or "Unknown error"))
      end
    end
  end

  if #err_msgs > 0 then
    vim.notify("[replace_by_ai] Some code blocks failed:\n" .. table.concat(err_msgs, "\n"), vim.log.levels.ERROR)
  else
    vim.notify("[replace_by_ai] Applied all code blocks successfully.", vim.log.levels.INFO)
  end
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

  vim.api.nvim_set_keymap("n",
    M.config.mappings.send_to_ai,
    "<Cmd>lua require('compose-ai-message').send_to_ai()<CR>",
    opts)

  vim.api.nvim_set_keymap("n",
    M.config.mappings.replace_by_ai,
    "<Cmd>lua require('compose-ai-message').replace_by_ai()<CR>",
    { noremap=true, silent=true }
  )
end

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})

  M.setup_mappings()

  M.reset()
end

return M
