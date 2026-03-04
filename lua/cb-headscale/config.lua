local M = {}

---@class CbHeadscaleConfig
---@field enabled boolean
---@field scale_map table<integer, integer>  heading level -> scale factor
---@field valign integer  vertical alignment: 0=top, 1=bottom, 2=center
---@field halign integer  horizontal alignment: 0=left, 1=right, 2=center
---@field anti_conceal boolean  show raw markdown when cursor is on heading
---@field debug boolean

---@type CbHeadscaleConfig
M.defaults = {
	enabled = true,
	scale_map = {
		[1] = 3, -- h1: triple size (3 rows)
		[2] = 2, -- h2: double size (2 rows)
	},
	valign = 2, -- centered
	halign = 0, -- left
	anti_conceal = true,
	debug = false,
}

---@type CbHeadscaleConfig
M.current = vim.deepcopy(M.defaults)

---@param user_opts table|nil
function M.setup(user_opts)
	M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
end

return M
