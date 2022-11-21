local async = require("neotest.async")
local lib = require("neotest.lib")
local FanoutAccum = require("neotest.types").FanoutAccum

local M = {
  job = nil,
  result_code = nil,
  finish_cond = nil,
  data_accum = nil,
  attach_win = nil,
  attach_buf = nil,
  attach_chan = nil,
  output_path = nil,
  output_fd = nil,
}

local function make_output_path()
  local output_path = async.fn.tempname()
  print("Output path", output_path)
  local open_err, output_fd = async.uv.fs_open(output_path, "w", 438)
  assert(not open_err, open_err)

  M.data_accum:subscribe(function(data)
    local write_err, _ = async.uv.fs_write(output_fd, data)
    assert(not write_err, write_err)
  end)

  M.output_path = output_path
  M.output_fd = output_fd
end

local function ensure_started(spec)
  if M.job then
    return true
  end

  local env, cwd, command = spec.env, spec.cwd, spec.command

  M.finish_cond = async.control.Condvar.new()
  M.result_code = nil
  M.data_accum = FanoutAccum(function(prev, new)
    if not prev then
      return new
    end
    return prev .. new
  end, nil)

  M.attach_win = nil
  M.attach_buf = nil
  M.attach_chan = nil

  make_output_path()

  local success, job = pcall(async.fn.jobstart, command, {
    cwd = cwd,
    env = env,
    pty = true,
    height = spec.strategy.height or 40,
    width = spec.strategy.width or 120,
    on_stdout = function(_, data)
      async.run(function()
        M.data_accum:push(table.concat(data, "\n"))
      end)
    end,
    on_exit = function(_, code)
      M.result_code = code
      M.finish_cond:notify_all()
    end,
  })
  if not success then
    local write_err, _ = async.uv.fs_write(M.output_fd, job)
    assert(not write_err, write_err)
    M.result_code = 1
    M.finish_cond:notify_all()
  end

  M.job = job
  return success
end

local function write_test_args(spec)
  local test_args = spec.strategy.test_args
  local input = table.concat(test_args, " ")
  async.api.nvim_chan_send(M.job, input .. "\n")
end

---@class iexStrategyConfig
---@field height integer
---@field width integer

---@async
---@param spec neotest.RunSpec
---@return neotest.Process
return function(spec)
  local success = ensure_started(spec)
  if success then
    write_test_args(spec)
  end

  return {
    is_complete = function()
      return M.result_code ~= nil
    end,
    output = function()
      return M.output_path
    end,
    stop = function()
      async.fn.jobstop(M.job)
      M.job = nil
    end,
    output_stream = function()
      local sender, receiver = async.control.channel.mpsc()
      M.data_accum:subscribe(function(d)
        sender.send(d)
      end)
      return function()
        return async.lib.first(function()
          M.finish_cond:wait()
        end, receiver.recv)
      end
    end,
    attach = function()
      if not M.attach_buf then
        M.attach_buf = async.api.nvim_create_buf(false, true)
        M.attach_chan = lib.ui.open_term(M.attach_buf, {
          on_input = function(_, _, _, data)
            pcall(async.api.nvim_chan_send, M.job, data)
          end,
        })
        M.data_accum:subscribe(function(data)
          async.api.nvim_chan_send(M.attach_chan, data)
        end)
      end
      M.attach_win = lib.ui.float.open({
        height = spec.strategy.height or 40,
        width = spec.strategy.width or 120,
        buffer = M.attach_buf,
      })
      vim.api.nvim_buf_set_option(M.attach_buf, "filetype", "neotest-attach")
      M.attach_win:jump_to()
    end,
    result = function()
      if M.result_code == nil then
        M.finish_cond:wait()
      end
      local close_err = async.uv.fs_close(M.output_fd)
      assert(not close_err, close_err)
      pcall(async.fn.chanclose, M.job)
      M.job = nil
      if M.attach_win then
        M.attach_win:listen("close", function()
          pcall(vim.api.nvim_buf_delete, M.attach_buf, { force = true })
          pcall(vim.fn.chanclose, M.attach_chan)
        end)
      end
      return M.result_code
    end,
  }
end
