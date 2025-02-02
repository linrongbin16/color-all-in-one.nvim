local cwd = vim.fn.getcwd()

describe("colorbox.controller", function()
  local assert_eq = assert.is_equal
  local assert_true = assert.is_true
  local assert_false = assert.is_false

  before_each(function()
    vim.api.nvim_command("cd " .. cwd)
  end)

  local str = require("colorbox.commons.str")
  local controller = require("colorbox.controller")
  require("colorbox").setup({
    debug = true,
    file_log = true,
  })

  local github_actions = os.getenv("GITHUB_ACTIONS") == "true"

  describe("[_parse_args]", function()
    it("test1", function()
      local actual1 = controller._parse_args("scale=0.7")
      print(string.format("_parse_args-1:%s\n", vim.inspect(actual1)))
      assert_eq(type(actual1), "table")
      assert_eq(actual1.scale, "0.7")
    end)
    it("test2", function()
      local actual2 = controller._parse_args("")
      assert_eq(actual2, nil)
    end)
    it("test3", function()
      local actual3 = controller._parse_args()
      assert_eq(actual3, nil)
    end)
    it("test4", function()
      local actual4 = controller._parse_args("a=")
      print(string.format("_parse_args-4:%s\n", vim.inspect(actual4)))
      assert_eq(type(actual4), "table")
      assert_true(str.empty(actual4.a))
    end)
  end)
end)
