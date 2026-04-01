return {
  'laytan/cloak.nvim',
  config = function()
    require('cloak').setup {
      enabled = true,
      cloak_character = '*',
      highlight_group = 'Comment',
      cloak_length = nil,
      try_all_patterns = true,
      patterns = {
        {
          file_pattern = '.env*',
          cloak_pattern = '=.+',
          replace = nil,
        },
      },
    }

    vim.keymap.set('n', '<leader>tc', '<cmd>CloakToggle<CR>', { desc = '[T]oggle [C]loak' })
    vim.keymap.set('n', '<leader>tp', '<cmd>CloakPreviewLine<CR>', { desc = '[T]oggle Cloak [P]review line' })
  end,
}
