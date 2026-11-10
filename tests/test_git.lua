local git = require("nvim-feedback.git")
local helpers = dofile("tests/helpers.lua")

local NUMBERED_LINES = vim.tbl_map(function(index)
  return "line " .. index
end, vim.fn.range(1, 20))

local repository = nil

local function create_repository()
  repository = helpers.create_repository()
end

local function remove_repository()
  helpers.remove(repository)
end

local function with_lines(changes)
  local lines = vim.deepcopy(NUMBERED_LINES)
  for index, line in pairs(changes) do
    lines[index] = line
  end
  return lines
end

local function anchored(lines, range)
  return {
    range = range,
    anchor = git.snapshot(
      repository,
      "file.txt",
      lines,
      range.start_line,
      range.end_line,
      range.start_col,
      range.end_col
    ),
  }
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = create_repository,
    post_case = remove_repository,
  },
})

tests["root()"] = MiniTest.new_set()

tests["root()"]["returns the top level of the repository that contains the file"] = function()
  local file_path = helpers.write_file(repository, "nested/directory/file.txt", { "content" })

  MiniTest.expect.equality(git.root(file_path), repository)
end

tests["root()"]["returns nil for a file outside a Git repository"] = function()
  local directory = helpers.temporary_directory()
  local file_path = helpers.write_file(directory, "file.txt", { "content" })

  MiniTest.expect.equality(git.root(file_path), nil)

  helpers.remove(directory)
end

tests["branch()"] = MiniTest.new_set()

tests["branch()"]["returns the checked out branch"] = function()
  helpers.git(repository, { "checkout", "--quiet", "-b", "feature" })

  MiniTest.expect.equality(git.branch(repository), "feature")
end

tests["branch()"]["returns nil when HEAD is detached"] = function()
  helpers.write_file(repository, "file.txt", { "content" })
  helpers.commit(repository)
  helpers.git(repository, { "checkout", "--quiet", "--detach" })

  MiniTest.expect.equality(git.branch(repository), nil)
end

tests["relative()"] = MiniTest.new_set()

tests["relative()"]["returns the path of a file relative to the repository"] = function()
  MiniTest.expect.equality(git.relative("/repository", "/repository/lua/file.lua"), "lua/file.lua")
end

tests["relative()"]["returns nil for a file outside the repository"] = function()
  MiniTest.expect.equality(git.relative("/repository", "/repository-copy/file.lua"), nil)
end

tests["snapshot()"] = MiniTest.new_set()

tests["snapshot()"]["records the selected lines and up to three lines of context on each side"] = function()
  local snapshot = git.snapshot(repository, "file.txt", NUMBERED_LINES, 2, 3)

  MiniTest.expect.equality(snapshot, {
    head = vim.NIL,
    selected_lines = { "line 2", "line 3" },
    context_before = { "line 1" },
    context_after = { "line 4", "line 5", "line 6" },
    diff_hunk = vim.NIL,
  })
end

tests["snapshot()"]["records the commit at HEAD"] = function()
  helpers.write_file(repository, "file.txt", NUMBERED_LINES)
  helpers.commit(repository)

  local snapshot = git.snapshot(repository, "file.txt", NUMBERED_LINES, 1, 1)

  MiniTest.expect.equality(snapshot.head, helpers.git(repository, { "rev-parse", "HEAD" }))
  MiniTest.expect.equality(snapshot.diff_hunk, vim.NIL)
end

tests["snapshot()"]["records only the uncommitted hunks that touch the selection"] = function()
  helpers.write_file(repository, "file.txt", NUMBERED_LINES)
  helpers.commit(repository)
  local lines = with_lines({ [2] = "changed 2", [18] = "changed 18" })
  helpers.write_file(repository, "file.txt", lines)

  local first_hunk = table.concat({
    "@@ -1,5 +1,5 @@",
    " line 1",
    "-line 2",
    "+changed 2",
    " line 3",
    " line 4",
    " line 5",
  }, "\n")
  local second_hunk = table.concat({
    "@@ -15,6 +15,6 @@ line 14",
    " line 15",
    " line 16",
    " line 17",
    "-line 18",
    "+changed 18",
    " line 19",
    " line 20",
  }, "\n")
  MiniTest.expect.equality(git.snapshot(repository, "file.txt", lines, 18, 18).diff_hunk, second_hunk)
  MiniTest.expect.equality(
    git.snapshot(repository, "file.txt", lines, 2, 18).diff_hunk,
    first_hunk .. "\n" .. second_hunk
  )
  MiniTest.expect.equality(git.snapshot(repository, "file.txt", lines, 10, 10).diff_hunk, vim.NIL)
end

tests["snapshot()"]["records a hunk whose header omits the line count"] = function()
  helpers.write_file(repository, "file.txt", { "one" })
  helpers.commit(repository)
  helpers.write_file(repository, "file.txt", { "uno" })

  local snapshot = git.snapshot(repository, "file.txt", { "uno" }, 1, 1)

  MiniTest.expect.equality(snapshot.diff_hunk, "@@ -1 +1 @@\n-one\n+uno")
end

tests["snapshot()"]["records the text of a characterwise selection on one line"] = function()
  local snapshot = git.snapshot(repository, "file.txt", { "local value = compute(1)" }, 1, 1, 14, 21)

  MiniTest.expect.equality(snapshot.selected_text, "compute")
  MiniTest.expect.equality(snapshot.selected_block, nil)
end

tests["snapshot()"]["records the text of a characterwise selection across lines"] = function()
  local snapshot = git.snapshot(repository, "file.txt", { "first line", "second line" }, 1, 2, 6, 6)

  MiniTest.expect.equality(snapshot.selected_text, "line\nsecond")
end

tests["snapshot()"]["records the text of each line of a blockwise selection"] = function()
  local columns = { { start_col = 0, end_col = 2 }, { start_col = 0, end_col = 0 } }

  local snapshot = git.snapshot(repository, "file.txt", { "abc", "" }, 1, 2, nil, nil, columns)

  MiniTest.expect.equality(snapshot.selected_block, { "ab", "" })
  MiniTest.expect.equality(snapshot.selected_text, nil)
end

tests["locate()"] = MiniTest.new_set()

tests["locate()"]["finds whole lines that have not moved"] = function()
  local item = anchored({ "alpha", "target", "beta" }, { start_line = 2, end_line = 2 })

  MiniTest.expect.equality({ git.locate({ "alpha", "target", "beta" }, item) }, { 2, 2 })
end

tests["locate()"]["finds whole lines that moved"] = function()
  local item = anchored({ "alpha", "target", "more", "beta" }, { start_line = 2, end_line = 3 })

  MiniTest.expect.equality({ git.locate({ "new", "new", "alpha", "target", "more", "beta" }, item) }, { 4, 5 })
end

tests["locate()"]["prefers the copy of the lines whose surrounding lines still match"] = function()
  local item = anchored({ "alpha", "target", "beta" }, { start_line = 2, end_line = 2 })

  local lines = { "target", "one", "two", "three", "alpha", "target", "beta" }
  MiniTest.expect.equality({ git.locate(lines, item) }, { 6, 6 })
end

tests["locate()"]["prefers the closest copy of the lines when their context matches equally"] = function()
  local item = anchored({ "alpha", "target", "beta" }, { start_line = 2, end_line = 2 })

  MiniTest.expect.equality({ git.locate({ "target", "x", "y", "z", "target" }, item) }, { 1, 1 })
end

tests["locate()"]["returns nil when two copies of the lines are equally good matches"] = function()
  local item = anchored({ "alpha", "target", "beta" }, { start_line = 2, end_line = 2 })

  MiniTest.expect.equality({ git.locate({ "target", "x", "target" }, item) }, {})
end

tests["locate()"]["finds whole lines that moved up in a file that got shorter"] = function()
  local item = anchored({ "alpha", "beta", "gamma", "target" }, { start_line = 4, end_line = 4 })

  MiniTest.expect.equality({ git.locate({ "target", "alpha" }, item) }, { 1, 1 })
end

tests["locate()"]["returns nil when the lines are gone"] = function()
  local item = anchored({ "alpha", "target", "beta" }, { start_line = 2, end_line = 2 })

  MiniTest.expect.equality({ git.locate({ "alpha", "beta" }, item) }, {})
end

tests["locate()"]["finds selected text that has not moved"] = function()
  local lines = { "local value = compute(1)" }
  local item = anchored(lines, { start_line = 1, end_line = 1, start_col = 14, end_col = 21 })

  MiniTest.expect.equality({ git.locate(lines, item) }, { 1, 1, 14, 21 })
end

tests["locate()"]["finds selected text that moved to another line and column"] = function()
  local item = anchored({ "local value = compute(1)" }, { start_line = 1, end_line = 1, start_col = 14, end_col = 21 })

  local lines = { "-- header", "local result = compute(1)" }
  MiniTest.expect.equality({ git.locate(lines, item) }, { 2, 2, 15, 22 })
end

tests["locate()"]["finds selected text that spans lines after it moved"] = function()
  local item = anchored({ "first line", "second line" }, { start_line = 1, end_line = 2, start_col = 6, end_col = 6 })

  MiniTest.expect.equality({ git.locate({ "zero", "first line", "second line" }, item) }, { 2, 3, 6, 6 })
end

tests["locate()"]["prefers the copy of the selected text closest to its original column"] = function()
  local item = anchored({ "a = f(x)" }, { start_line = 1, end_line = 1, start_col = 4, end_col = 5 })

  MiniTest.expect.equality({ git.locate({ "f f" }, item) }, { 1, 1, 2, 3 })
end

tests["locate()"]["prefers the copy of the selected text on the closest line"] = function()
  local item = anchored({ "alpha", "call()", "beta" }, { start_line = 2, end_line = 2, start_col = 0, end_col = 4 })

  MiniTest.expect.equality({ git.locate({ "call()", "x", "y", "z", "call()" }, item) }, { 1, 1, 0, 4 })
end

tests["locate()"]["returns nil when two copies of the selected text are equally good matches"] = function()
  local item = anchored({ "a = f(x)" }, { start_line = 1, end_line = 1, start_col = 4, end_col = 5 })

  MiniTest.expect.equality({ git.locate({ "  f   f" }, item) }, {})
end

tests["locate()"]["returns nil when the selected text is gone"] = function()
  local item = anchored({ "local value = compute(1)" }, { start_line = 1, end_line = 1, start_col = 14, end_col = 21 })

  MiniTest.expect.equality({ git.locate({ "local value = 1" }, item) }, {})
end

return tests
