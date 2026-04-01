return {
  'tpope/vim-sleuth',
  -- Load early to detect indentation before other plugins
  event = { 'BufReadPre', 'BufNewFile' },
}
