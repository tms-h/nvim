return {
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")

      local function get_cat()
        local hour = tonumber(os.date("%H"))

        if hour >= 22 or hour < 5 then
          return {
            [[   .    *    .   *   .    *    .   *  ]],
            [[      .   *      .      *   .         ]],
            [[   *       .          *       .    *  ]],
            [[]],
            [[          |\      _,,,---,,_          ]],
            [[    ZZZzz /,`.-'`'    -.  ;-;;,_     ]],
            [[         |,4-  ) )-,_. ,\ (  `'-'    ]],
            [[        '---''(_/--'  `-'\_)         ]],
            [[   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]],
          }, "go to sleep..."

        elseif hour >= 5 and hour < 9 then
          return {
            [[      ~ ~    ~  ~    ~ ~    ~  ~      ]],
            [[        ~  ~    ~  ~    ~  ~    ~     ]],
            [[]],
            [[        /\-/\                         ]],
            [[       /o o  \                _       ]],
            [[      =\ Y  =/-~~~~~~-,_____/ )      ]],
            [[        '^--'          ______/        ]],
            [[          \           /               ]],
            [[         ||  |---'\  \                ]],
            [=[        (__(|     ((__)              ]=],
            [[   _____________________________________]],
            [[     {_}  )~~                           ]],
          }, "morning. coffee first."

        elseif hour >= 9 and hour < 13 then
          return {
            [[]],
            [[          |\__/,|   (`\               ]],
            [[          |_ _  |.--.) )              ]],
            [[          ( T   )     /               ]],
            [[         (((^_(((/(((_/               ]],
            [[   _____________________________________]],
            [[     {_}    .----.                      ]],
            [[           | // |                      ]],
            [[           '----'                      ]],
          }, "ready to build"

        elseif hour >= 13 and hour < 17 then
          return {
            [[   .-------------------------------------.]],
            [[   |                                      |]],
            [[   |            |\___/|                   |]],
            [[   |            )     (                   |]],
            [[   |           =\     /=                  |]],
            [[   |             )===(                    |]],
            [[   |            /     \                   |]],
            [[   |           |       |                  |]],
            [[   |            \_   _/                   |]],
            [[   |______________________________________|]],
          }, "deep focus"

        else
          return {
            [[   .    *    .        .    *    .      ]],
            [[]],
            [[          |\__/,|   (`\               ]],
            [[          |_ _  |.--.) )              ]],
            [[          ( T   )     /               ]],
            [[         (((^_(((/(((_/               ]],
            [[   _____________________________________]],
            [[                          {_}  )~~      ]],
          }, "winding down"
        end
      end

      local cat, greeting = get_cat()
      local header = { "", "" }
      for _, line in ipairs(cat) do
        table.insert(header, line)
      end
      table.insert(header, "")

      dashboard.section.header.val = header

      local buttons = {
        dashboard.button("f", "  find file", "<cmd>Telescope find_files<cr>"),
        dashboard.button("r", "  recent", "<cmd>Telescope oldfiles<cr>"),
        dashboard.button("g", "  grep", "<cmd>Telescope live_grep<cr>"),
        dashboard.button("n", "  new file", "<cmd>enew<cr>"),
        dashboard.button("l", "  leetcode", "<cmd>Leet<cr>"),
        dashboard.button("c", "  config", "<cmd>e $MYVIMRC<cr>"),
        dashboard.button("q", "  quit", "<cmd>qa<cr>"),
      }

      for _, btn in ipairs(buttons) do
        local sc = btn.opts.shortcut
        local start = btn.val:find("[%a]")
        if start then
          local pos = btn.val:lower():find(sc:lower(), start, true)
          if pos then
            btn.opts.hl = { { "AlphaButtonShortcut", pos - 1, pos } }
          end
        end
      end

      dashboard.section.buttons.val = buttons

      dashboard.section.footer.val = greeting

      dashboard.section.header.opts.hl = "AlphaHeader"
      dashboard.section.footer.opts.hl = "AlphaFooter"

      alpha.setup(dashboard.config)

      vim.api.nvim_set_hl(0, "AlphaHeader", { fg = "#dbbc7f" })
      vim.api.nvim_set_hl(0, "AlphaFooter", { fg = "#7a8478", italic = true })
      vim.api.nvim_set_hl(0, "AlphaButtonShortcut", { underline = true })
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.api.nvim_set_hl(0, "AlphaHeader", { fg = "#dbbc7f" })
          vim.api.nvim_set_hl(0, "AlphaFooter", { fg = "#7a8478", italic = true })
          vim.api.nvim_set_hl(0, "AlphaButtonShortcut", { underline = true })
        end,
      })
    end,
  },
}
