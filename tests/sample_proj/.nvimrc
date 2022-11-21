lua << EOF
if not pcall(require, "neotest") then
  return
end

vim.schedule(function()
  require("neotest").setup_project(vim.loop.cwd(), {
    adapters = {
      require("neotest-elixir")({ mix_task = "test", extra_formatters = {"ExUnit.CLIFormatter", "ExUnitNotifier"} }),
    },
  })
end)
EOF
