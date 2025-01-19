local M = {}

function M.is_test_file(file_path, pattern)
  return file_path:match(pattern)
end

return M
