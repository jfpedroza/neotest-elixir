local M = {}

function M.is_test_file(file_path)
  return vim.endswith(file_path, "_test.exs")
end

return M
