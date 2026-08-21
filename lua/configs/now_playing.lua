local M = {}

local text = ""
local running = false
local timer
local executable = vim.fn.exepath "nowplaying-cli"

local function clean(value)
  value = vim.trim(value or "")
  if value == "null" or value == "(null)" then
    return ""
  end
  local cleaned = value:gsub("[\r\n]+", " ")
  return cleaned
end

local function truncate(value, max_width)
  if vim.fn.strdisplaywidth(value) <= max_width then
    return value
  end

  local length = vim.fn.strchars(value)
  repeat
    length = length - 1
    value = vim.fn.strcharpart(value, 0, length)
  until length == 0 or vim.fn.strdisplaywidth(value .. "…") <= max_width

  return value .. "…"
end

local function refresh_statusline()
  pcall(function()
    require("lualine").refresh { scope = "all", place = { "statusline" } }
  end)
end

local function poll()
  if running or executable == "" then
    return
  end
  running = true

  vim.system({ executable, "get", "title", "artist", "playbackRate" }, { text = true }, function(result)
    vim.schedule(function()
      running = false

      local next_text = ""
      if result.code == 0 then
        local lines = vim.split(result.stdout or "", "\n", { plain = true })
        local title = clean(lines[1])
        local artist = clean(lines[2])
        local playback_rate = tonumber(clean(lines[3]))

        if title ~= "" then
          local track = artist ~= "" and (title .. " — " .. artist) or title
          -- Spotify exposes a numeric rate while playing and null while paused.
          local icon = playback_rate and playback_rate > 0 and "" or ""
          next_text = icon .. " " .. truncate(track:lower(), 48)
        end
      end

      if next_text ~= text then
        text = next_text
        refresh_statusline()
      end
    end)
  end)
end

function M.setup()
  if timer or vim.fn.has "macunix" ~= 1 or executable == "" then
    return
  end

  poll()
  timer = vim.uv.new_timer()
  timer:start(2000, 2000, vim.schedule_wrap(poll))

  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
    end,
  })
end

function M.statusline()
  return text
end

return M
