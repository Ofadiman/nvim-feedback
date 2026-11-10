local helpers = dofile("tests/helpers.lua")
local store = require("nvim-feedback.store")

local INVALID_ITEMS = {
  {
    "an item that is not a table",
    function(data)
      data.feedback[1] = "comment"
    end,
  },
  {
    "an empty branch",
    function(data)
      data.feedback[1].branch = ""
    end,
  },
  {
    "an empty id",
    function(data)
      data.feedback[1].id = ""
    end,
  },
  {
    "an empty file",
    function(data)
      data.feedback[1].file = ""
    end,
  },
  {
    "an absolute file path",
    function(data)
      data.feedback[1].file = "/etc/hosts"
    end,
  },
  {
    "a file path outside the repository",
    function(data)
      data.feedback[1].file = "../values.lua"
    end,
  },
  {
    "a blank comment",
    function(data)
      data.feedback[1].comment = " \n "
    end,
  },
  {
    "an empty creation time",
    function(data)
      data.feedback[1].created_at = ""
    end,
  },
  {
    "a missing range",
    function(data)
      data.feedback[1].range = nil
    end,
  },
  {
    "a fractional start line",
    function(data)
      data.feedback[1].range.start_line = 1.5
    end,
  },
  {
    "a start line before the first line",
    function(data)
      data.feedback[1].range.start_line = 0
    end,
  },
  {
    "an end line before the start line",
    function(data)
      data.feedback[1].range.end_line = 0
    end,
  },
  {
    "a missing anchor",
    function(data)
      data.feedback[1].anchor = nil
    end,
  },
  {
    "a head that is not a string",
    function(data)
      data.feedback[1].anchor.head = 1
    end,
  },
  {
    "more selected lines than the range covers",
    function(data)
      table.insert(data.feedback[1].anchor.selected_lines, "extra")
    end,
  },
  {
    "a selected line that is not a string",
    function(data)
      data.feedback[1].anchor.selected_lines = { 1 }
    end,
  },
  {
    "context lines that are not a list",
    function(data)
      data.feedback[1].anchor.context_after = { first = "line" }
    end,
  },
  {
    "a diff hunk that is not a string",
    function(data)
      data.feedback[1].anchor.diff_hunk = 1
    end,
  },
  {
    "selected text without columns",
    function(data)
      data.feedback[1].anchor.selected_text = "local"
    end,
  },
  {
    "a start column without an end column",
    function(data)
      data.feedback[1].range.start_col = 0
    end,
  },
  {
    "columns that are not numbers",
    function(data)
      data.feedback[1].range.start_col = "0"
      data.feedback[1].range.end_col = "5"
      data.feedback[1].anchor.selected_text = "local"
    end,
  },
  {
    "a negative column",
    function(data)
      data.feedback[1].range.start_col = -1
      data.feedback[1].range.end_col = 5
      data.feedback[1].anchor.selected_text = "local"
    end,
  },
  {
    "an end column at the start column on one line",
    function(data)
      data.feedback[1].range.start_col = 5
      data.feedback[1].range.end_col = 5
      data.feedback[1].anchor.selected_text = "local"
    end,
  },
  {
    "columns without selected text",
    function(data)
      data.feedback[1].range.start_col = 0
      data.feedback[1].range.end_col = 5
    end,
  },
  {
    "a selected block without columns",
    function(data)
      data.feedback[1].anchor.selected_block = { "local" }
    end,
  },
  {
    "block columns together with a start column",
    function(data)
      data.feedback[1].range.start_col = 0
      data.feedback[1].range.end_col = 5
      data.feedback[1].range.columns = { { start_col = 0, end_col = 5 } }
      data.feedback[1].anchor.selected_text = "local"
      data.feedback[1].anchor.selected_block = { "local" }
    end,
  },
  {
    "block columns that are not a list",
    function(data)
      data.feedback[1].range.columns = { first = { start_col = 0, end_col = 5 } }
      data.feedback[1].anchor.selected_block = { "local" }
    end,
  },
  {
    "a block column that is not a table",
    function(data)
      data.feedback[1].range.columns = { 0 }
      data.feedback[1].anchor.selected_block = { "local" }
    end,
  },
  {
    "a block column that ends before it starts",
    function(data)
      data.feedback[1].range.columns = { { start_col = 5, end_col = 0 } }
      data.feedback[1].anchor.selected_block = { "local" }
    end,
  },
  {
    "a block that covers no text",
    function(data)
      data.feedback[1].range.columns = { { start_col = 0, end_col = 0 } }
      data.feedback[1].anchor.selected_block = { "" }
    end,
  },
  {
    "a duplicate id",
    function(data)
      table.insert(data.feedback, vim.deepcopy(data.feedback[1]))
    end,
  },
  {
    "feedback that is not a list",
    function(data)
      data.feedback = { first = data.feedback[1] }
    end,
  },
}

local repository = nil

local function valid_data()
  return {
    feedback = {
      {
        id = "first",
        branch = "main",
        file = "values.lua",
        comment = "Rename this",
        created_at = "2026-11-10T00:00:00Z",
        range = { start_line = 1, end_line = 1 },
        anchor = {
          head = vim.NIL,
          selected_lines = { "local value = 1" },
          context_before = {},
          context_after = {},
          diff_hunk = vim.NIL,
        },
      },
    },
  }
end

local function feedback_path()
  return vim.fs.joinpath(repository, "feedback.json")
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      repository = helpers.temporary_directory()
    end,
    post_case = function()
      helpers.remove(repository)
    end,
  },
})

tests["path()"] = MiniTest.new_set()

tests["path()"]["returns feedback.json in the repository root"] = function()
  MiniTest.expect.equality(store.path(repository), feedback_path())
end

tests["read()"] = MiniTest.new_set()

tests["read()"]["returns no feedback when feedback.json does not exist"] = function()
  MiniTest.expect.equality({ store.read(repository) }, { { feedback = {} } })
end

tests["read()"]["returns the feedback stored in feedback.json"] = function()
  vim.fn.writefile({ vim.json.encode(valid_data()) }, feedback_path())

  MiniTest.expect.equality({ store.read(repository) }, { valid_data() })
end

tests["read()"]["reports feedback.json that is not JSON"] = function()
  vim.fn.writefile({ "{" }, feedback_path())

  MiniTest.expect.equality({ store.read(repository) }, { nil, "Invalid AI feedback file: " .. feedback_path() })
end

tests["read()"]["reports feedback.json that holds invalid feedback"] = function()
  vim.fn.writefile({ vim.json.encode({ feedback = { { id = "first" } } }) }, feedback_path())

  MiniTest.expect.equality({ store.read(repository) }, { nil, "Invalid AI feedback file: " .. feedback_path() })
end

tests["write()"] = MiniTest.new_set()

tests["write()"]["stores the feedback as one line of JSON"] = function()
  MiniTest.expect.equality(store.write(repository, valid_data()), true)

  local lines = vim.fn.readfile(feedback_path())
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(vim.json.decode(lines[1]), valid_data())
end

tests["write()"]["accepts a characterwise comment"] = function()
  local data = valid_data()
  data.feedback[1].range.start_col = 6
  data.feedback[1].range.end_col = 11
  data.feedback[1].anchor.selected_text = "value"

  MiniTest.expect.equality(store.write(repository, data), true)
end

tests["write()"]["reports a directory it cannot write to"] = function()
  local missing_directory = vim.fs.joinpath(repository, "missing")

  local ok, write_error = store.write(missing_directory, valid_data())

  MiniTest.expect.equality(ok, nil)
  MiniTest.expect.equality(type(write_error), "string")
end

tests["write()"]["reports a feedback.json it cannot replace and removes its temporary file"] = function()
  vim.fn.mkdir(feedback_path(), "p")

  local ok, write_error = store.write(repository, valid_data())

  MiniTest.expect.equality(ok, nil)
  MiniTest.expect.equality(type(write_error), "string")
  MiniTest.expect.equality(vim.fn.readdir(repository), { "feedback.json" })
end

for _, case in ipairs(INVALID_ITEMS) do
  local description, invalidate = case[1], case[2]
  tests["write()"]["rejects " .. description] = function()
    local data = valid_data()
    invalidate(data)

    MiniTest.expect.equality({ store.write(repository, data) }, { nil, "Refusing to write invalid AI feedback data" })
    MiniTest.expect.equality(vim.uv.fs_stat(feedback_path()), nil)
  end
end

tests["write()"]["rejects data without a feedback list"] = function()
  MiniTest.expect.equality({ store.write(repository, {}) }, { nil, "Refusing to write invalid AI feedback data" })
end

tests["mutate()"] = MiniTest.new_set()

tests["mutate()"]["writes the data the callback changed and returns its result"] = function()
  local result = store.mutate(repository, function(data)
    table.insert(data.feedback, valid_data().feedback[1])
    return true, 1
  end)

  MiniTest.expect.equality(result, 1)
  MiniTest.expect.equality({ store.read(repository) }, { valid_data() })
end

tests["mutate()"]["returns true when the callback returns no result"] = function()
  local result = store.mutate(repository, function()
    return false
  end)

  MiniTest.expect.equality(result, true)
end

tests["mutate()"]["does not write when the callback reports no change"] = function()
  store.mutate(repository, function(data)
    table.insert(data.feedback, valid_data().feedback[1])
    return false
  end)

  MiniTest.expect.equality(vim.uv.fs_stat(feedback_path()), nil)
end

tests["mutate()"]["returns the error of the callback without writing"] = function()
  local result = {
    store.mutate(repository, function(data)
      table.insert(data.feedback, valid_data().feedback[1])
      return true, nil, "AI feedback no longer exists"
    end),
  }

  MiniTest.expect.equality(result, { nil, "AI feedback no longer exists" })
  MiniTest.expect.equality(vim.uv.fs_stat(feedback_path()), nil)
end

tests["mutate()"]["returns the error of reading feedback.json without calling the callback"] = function()
  vim.fn.writefile({ "{" }, feedback_path())
  local called = false

  local result = {
    store.mutate(repository, function()
      called = true
      return false
    end),
  }

  MiniTest.expect.equality(result, { nil, "Invalid AI feedback file: " .. feedback_path() })
  MiniTest.expect.equality(called, false)
end

tests["mutate()"]["returns the error of writing data the callback made invalid"] = function()
  local result = {
    store.mutate(repository, function(data)
      table.insert(data.feedback, "comment")
      return true
    end),
  }

  MiniTest.expect.equality(result, { nil, "Refusing to write invalid AI feedback data" })
end

tests["mtime()"] = MiniTest.new_set()

tests["mtime()"]["returns missing when feedback.json does not exist"] = function()
  MiniTest.expect.equality(store.mtime(repository), "missing")
end

tests["mtime()"]["changes when feedback.json changes"] = function()
  store.write(repository, valid_data())
  local before = store.mtime(repository)

  local data = valid_data()
  data.feedback[1].comment = "Rename this value"
  store.write(repository, data)

  MiniTest.expect.no_equality(store.mtime(repository), before)
  MiniTest.expect.equality(store.mtime(repository):match("^%d+:%d+:%d+$") ~= nil, true)
end

return tests
