return {
  'binajmen/review.nvim',
  lazy = false,
  opts = {
    signs = {
      enabled = true,
      text = 'R',
      hl = 'DiagnosticInfo',
      priority = 5,
    },
    virtual_lines = {
      enabled = true,
      prefix = '💬 ',
      hl = 'DiagnosticInfo',
    },
  },
  keys = {
    { '<leader>ra', '<Plug>(ReviewAdd)', mode = 'v', desc = 'Review: add comment on selection' },
    { '<leader>ra', '<Plug>(ReviewAdd)', mode = 'n', desc = 'Review: add file comment' },
    { '<leader>rl', '<Plug>(ReviewList)', desc = 'Review: list comments' },
    { '<leader>ry', '<Plug>(ReviewYank)', desc = 'Review: yank comments' },
    { '<leader>rc', '<Plug>(ReviewClear)', desc = 'Review: clear comments' },
  },
}
