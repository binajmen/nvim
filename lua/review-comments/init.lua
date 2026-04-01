-- review-comments.nvim
-- Annotate code with review comments and export them to clipboard.
--
-- Usage:
--   Visual-select lines, then <leader>ra  → add a comment
--   :ReviewList                            → show all comments in a floating window
--   :ReviewYank                            → yank all comments to clipboard (+ register)
--   :ReviewClear                           → clear all comments
--   :ReviewDelete <index>                  → delete a specific comment by number

local M = {}

---@class ReviewComment
---@field file string
---@field line_start integer
---@field line_end integer
---@field snippet? string
---@field comment string

---@type ReviewComment[]
M.comments = {}

--- Get the relative file path (relative to cwd), or absolute if outside.
---@return string
local function rel_path(bufnr)
  local full = vim.api.nvim_buf_get_name(bufnr or 0)
  local cwd = vim.fn.getcwd()
  if full:sub(1, #cwd) == cwd then
    return full:sub(#cwd + 2) -- strip cwd + trailing slash
  end
  return full
end

--- Open a small floating window for typing a comment.
--- Calls `on_done(text)` with the trimmed content when the user saves (:w or :wq).
---@param on_done fun(text: string)
---@param initial_text? string
local function open_comment_float(on_done, initial_text)
  -- Clean up any leftover buffer from a previous comment (e.g. if an error prevented cleanup)
  local existing = vim.fn.bufnr('review://comment')
  if existing ~= -1 then
    vim.api.nvim_buf_delete(existing, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'review://comment')

  local width = math.floor(vim.o.columns * 0.6)
  local height = 8
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Review Comment (save to confirm, :q to cancel) ',
    title_pos = 'center',
  })

  if initial_text then
    local init_lines = vim.split(initial_text, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, init_lines)
  end

  vim.cmd 'startinsert'

  -- Handle BufWriteCmd (since buftype=acwrite, :w triggers this instead of disk write)
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    once = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local text = vim.fn.trim(table.concat(lines, '\n'))
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
      if text ~= '' then
        on_done(text)
      else
        vim.notify('Review: empty comment, skipped.', vim.log.levels.WARN)
      end
    end,
  })

  -- Allow :q to cancel
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify('Review: comment cancelled.', vim.log.levels.INFO)
  end, { buffer = buf, nowait = true })
end

--- Add a comment for the current visual selection.
function M.add_comment()
  -- Get selection range ('< and '> marks are set when exiting visual mode).
  local line_start = vim.fn.line "'<"
  local line_end = vim.fn.line "'>"
  local bufnr = vim.api.nvim_get_current_buf()
  local file = rel_path(bufnr)
  local snippet_lines = vim.api.nvim_buf_get_lines(bufnr, line_start - 1, line_end, false)
  local snippet = table.concat(snippet_lines, '\n')

  open_comment_float(function(comment_text)
    table.insert(M.comments, {
      file = file,
      line_start = line_start,
      line_end = line_end,
      snippet = snippet,
      comment = comment_text,
    })
    vim.notify(string.format('Review: comment #%d added (%s:%d-%d)', #M.comments, file, line_start, line_end), vim.log.levels.INFO)
  end)
end

--- Add a file-level comment (no snippet).
function M.add_file_comment()
  local file = rel_path()

  open_comment_float(function(comment_text)
    table.insert(M.comments, {
      file = file,
      comment = comment_text,
    })
    vim.notify(string.format('Review: comment #%d added (%s)', #M.comments, file), vim.log.levels.INFO)
  end)
end

--- Build formatted lines and a mapping from line numbers to comment indices.
---@return string[], table<integer, integer> lines, line_to_comment
local function build_list_lines()
  local all_lines = {}
  local line_to_comment = {}

  for i, c in ipairs(M.comments) do
    local block
    if c.snippet then
      local ext = c.file:match '%.(%w+)$' or ''
      local line_label
      if c.line_start == c.line_end then
        line_label = string.format('line %d', c.line_start)
      else
        line_label = string.format('lines %d-%d', c.line_start, c.line_end)
      end
      block = string.format('## %d. %s (%s)\n```%s\n%s\n```\n**Comment:** %s', i, c.file, line_label, ext, c.snippet, c.comment)
    else
      block = string.format('## %d. %s\n**Comment:** %s', i, c.file, c.comment)
    end
    local block_lines = vim.split(block, '\n')

    if i > 1 then
      -- blank line before --- so markdown renders it as a rule, not a setext heading
      table.insert(all_lines, '')
      table.insert(all_lines, '---')
      table.insert(all_lines, '')
      line_to_comment[#all_lines - 2] = i
      line_to_comment[#all_lines - 1] = i
      line_to_comment[#all_lines] = i
    end

    local start = #all_lines + 1
    for _, l in ipairs(block_lines) do
      table.insert(all_lines, l)
    end
    for ln = start, #all_lines do
      line_to_comment[ln] = i
    end
  end

  return all_lines, line_to_comment
end

--- Format all comments into a markdown string.
---@return string
function M.format_comments()
  if #M.comments == 0 then
    return ''
  end
  local lines = build_list_lines()
  return table.concat(lines, '\n')
end

--- Show all comments in a floating window with edit/delete keymaps.
---@param jump_to_idx? integer  Comment index to jump to after opening
function M.list_comments(jump_to_idx)
  if #M.comments == 0 then
    vim.notify('Review: no comments yet.', vim.log.levels.INFO)
    return
  end

  local lines, line_to_comment = build_list_lines()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Review Comments (e=edit, d=delete, q=close) ',
    title_pos = 'center',
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function refresh()
    if #M.comments == 0 then
      close()
      vim.notify('Review: no comments left.', vim.log.levels.INFO)
      return
    end
    lines, line_to_comment = build_list_lines()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    local new_height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
    vim.api.nvim_win_set_height(win, new_height)
  end

  -- Jump to the requested comment's heading line
  if jump_to_idx then
    local heading = string.format('## %d.', jump_to_idx)
    for ln, line_text in ipairs(lines) do
      if line_text:find(heading, 1, true) then
        vim.api.nvim_win_set_cursor(win, { ln, 0 })
        break
      end
    end
  end

  vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })

  vim.keymap.set('n', 'd', function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local idx = line_to_comment[cursor_line]
    if not idx then return end
    table.remove(M.comments, idx)
    vim.notify(string.format('Review: deleted comment #%d.', idx), vim.log.levels.INFO)
    refresh()
  end, { buffer = buf, nowait = true })

  vim.keymap.set('n', 'e', function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local idx = line_to_comment[cursor_line]
    if not idx then return end
    close()
    open_comment_float(function(new_text)
      M.comments[idx].comment = new_text
      vim.notify(string.format('Review: updated comment #%d.', idx), vim.log.levels.INFO)
      -- Reopen the list and jump to the same comment
      vim.schedule(function()
        M.list_comments(idx)
      end)
    end, M.comments[idx].comment)
  end, { buffer = buf, nowait = true })
end

--- Yank all comments to the system clipboard.
function M.yank_comments()
  if #M.comments == 0 then
    vim.notify('Review: no comments to yank.', vim.log.levels.WARN)
    return
  end

  local text = M.format_comments()
  vim.fn.setreg('+', text)
  vim.notify(string.format('Review: %d comment(s) yanked to clipboard.', #M.comments), vim.log.levels.INFO)
end

--- Clear all comments.
function M.clear_comments()
  local count = #M.comments
  M.comments = {}
  vim.notify(string.format('Review: cleared %d comment(s).', count), vim.log.levels.INFO)
end

--- Delete a specific comment by index.
---@param index integer
function M.delete_comment(index)
  if index < 1 or index > #M.comments then
    vim.notify('Review: invalid comment index.', vim.log.levels.ERROR)
    return
  end
  table.remove(M.comments, index)
  vim.notify(string.format('Review: deleted comment #%d.', index), vim.log.levels.INFO)
end

--- Set up commands and keymaps.
function M.setup()
  -- Visual mode: add comment
  vim.keymap.set('v', '<leader>ra', function()
    -- Exit visual mode so that '< and '> marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
    M.add_comment()
  end, { desc = 'Review: add comment on selection', silent = true })

  -- Normal mode keymaps
  vim.keymap.set('n', '<leader>ra', M.add_file_comment, { desc = 'Review: add comment on file' })
  vim.keymap.set('n', '<leader>rl', M.list_comments, { desc = 'Review: list comments' })
  vim.keymap.set('n', '<leader>ry', M.yank_comments, { desc = 'Review: yank comments to clipboard' })
  vim.keymap.set('n', '<leader>rc', M.clear_comments, { desc = 'Review: clear all comments' })

  -- User commands
  vim.api.nvim_create_user_command('ReviewList', function()
    M.list_comments()
  end, {})
  vim.api.nvim_create_user_command('ReviewYank', function()
    M.yank_comments()
  end, {})
  vim.api.nvim_create_user_command('ReviewClear', function()
    M.clear_comments()
  end, {})
  vim.api.nvim_create_user_command('ReviewDelete', function(opts)
    M.delete_comment(tonumber(opts.args))
  end, { nargs = 1 })
end

return M
