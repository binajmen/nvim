return {
  'luiscassih/AniMotion.nvim',
  event = 'VeryLazy',
  config = function()
    require('AniMotion').setup {
      mode = 'helix',
      color = 'Visual',
    }
  end,
}
