-- Keep this config in step with GitHub on every machine. Startup pulls in the
-- background; pushing stays a deliberate keypress so half-finished edits never
-- reach the other machines.
local M = {}

local config_dir = vim.fn.stdpath "config"

local function git(args, on_done)
  vim.system(vim.list_extend({ "git", "-C", config_dir }, args), { text = true }, function(result)
    vim.schedule(function()
      on_done(result)
    end)
  end)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Config sync" })
end

local function first_line(result)
  local output = vim.trim((result.stderr ~= "" and result.stderr) or result.stdout or "")
  return output:match "[^\n]*" or ""
end

---Fast-forward to the remote when the checkout has no local edits.
function M.pull()
  git({ "status", "--porcelain" }, function(status)
    if status.code ~= 0 then
      return
    end
    if vim.trim(status.stdout) ~= "" then
      notify("Local config changes not synced yet. Press <leader>gs to sync.", vim.log.levels.WARN)
      return
    end

    git({ "pull", "--ff-only", "--quiet" }, function(pull)
      if pull.code ~= 0 then
        notify("Pull failed: " .. first_line(pull), vim.log.levels.WARN)
        return
      end
      git({ "rev-parse", "HEAD@{1}", "HEAD" }, function(revs)
        local before, after = unpack(vim.split(vim.trim(revs.stdout), "\n"))
        if revs.code == 0 and before ~= after then
          notify "Config updated from GitHub. Restart Neovim to apply."
        end
      end)
    end)
  end)
end

---Commit every local change, rebase onto the remote, and push.
function M.sync()
  git({ "add", "--all" }, function(add)
    if add.code ~= 0 then
      notify("git add failed: " .. first_line(add), vim.log.levels.ERROR)
      return
    end

    git({ "diff", "--cached", "--quiet" }, function(diff)
      local function push()
        git({ "pull", "--rebase", "--quiet" }, function(pull)
          if pull.code ~= 0 then
            notify("Pull failed, nothing pushed: " .. first_line(pull), vim.log.levels.ERROR)
            return
          end
          git({ "push", "--quiet" }, function(result)
            if result.code ~= 0 then
              notify("Push failed: " .. first_line(result), vim.log.levels.ERROR)
            else
              notify "Config synced to GitHub."
            end
          end)
        end)
      end

      if diff.code == 0 then
        push()
        return
      end

      vim.ui.input({ prompt = "Commit message: ", default = "chore: sync config" }, function(message)
        if not message or vim.trim(message) == "" then
          git({ "reset", "--quiet" }, function() end)
          notify "Sync cancelled."
          return
        end
        git({ "commit", "--quiet", "-m", message }, function(commit)
          if commit.code ~= 0 then
            notify("Commit failed: " .. first_line(commit), vim.log.levels.ERROR)
            return
          end
          push()
        end)
      end)
    end)
  end)
end

return M
