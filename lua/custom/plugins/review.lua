return {
  dir = vim.fn.stdpath('config') .. '/lua/review-comments',
  name = 'review-comments',
  event = 'VeryLazy',
  config = function()
    require('review-comments').setup()
  end,
}
