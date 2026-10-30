-- Keep this config in step with GitHub on every machine (Linux, Mac, Windows).
-- One second after startup it fast-forwards the config's git checkout in the
-- background. It never runs while the checkout has local edits or untracked
-- files, so half-finished work is never mixed with a pull; it then says so in
-- one line. A pull that changed something asks for a restart. Pushing stays a
-- deliberate git command. Tests set NVIM_NO_CONFIG_PULL=1.
local M = {}

local function git(args, on_done)
  local cmd = vim.list_extend({ "git", "-C", vim.fn.stdpath "config" }, args)
  local ok = pcall(vim.system, cmd, { text = true }, function(result)
    vim.schedule(function()
      on_done(result)
    end)
  end)
  if not ok then
    on_done { code = -1, stdout = "", stderr = "" }
  end
end

local function say(message, level)
  vim.notify("Config sync: " .. message, level or vim.log.levels.INFO)
end

local function first_line(result)
  local out = vim.trim((result.stderr ~= "" and result.stderr) or result.stdout or "")
  return out:match "[^\n]*"
end

---Fast-forward to the remote when the checkout has no local edits.
function M.pull()
  git({ "status", "--porcelain" }, function(status)
    if status.code ~= 0 then
      return -- not a git checkout (or no git): nothing to sync
    end
    if vim.trim(status.stdout) ~= "" then
      say("not pulled, the config folder has uncommitted or untracked files", vim.log.levels.WARN)
      return
    end
    git({ "rev-parse", "HEAD" }, function(before)
      git({ "pull", "--ff-only", "--quiet" }, function(pull)
        if pull.code ~= 0 then
          say("pull failed: " .. first_line(pull), vim.log.levels.WARN)
          return
        end
        git({ "rev-parse", "HEAD" }, function(after)
          if before.code == 0 and after.code == 0 and before.stdout ~= after.stdout then
            say "updated from GitHub, restart Neovim to apply"
          end
        end)
      end)
    end)
  end)
end

function M.setup()
  if vim.env.NVIM_NO_CONFIG_PULL == "1" then
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.defer_fn(M.pull, 1000)
    end,
  })
end

return M
