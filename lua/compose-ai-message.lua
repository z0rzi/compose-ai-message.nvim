local M = {
}

M.config = {
  mappings = {
  },
}

function M.setup(user_opts)
  M.config = vim.tbl_extend("force", M.config, user_opts or {})
end

return M
