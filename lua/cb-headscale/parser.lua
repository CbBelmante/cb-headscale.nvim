local M = {}

---@class HeadingInfo
---@field level integer         1-6
---@field text string           heading text (without # markers)
---@field start_row integer     0-indexed buffer line
---@field start_col integer     0-indexed buffer column
---@field end_row integer       0-indexed
---@field end_col integer
---@field marker_end_col integer  column where # markers + space end

--- Extract visible headings from a markdown buffer
---@param buf integer
---@param topline integer  1-indexed top visible line
---@param botline integer  1-indexed bottom visible line
---@param scale_map table<integer, integer>  which heading levels to handle
---@return HeadingInfo[]
function M.get_headings(buf, topline, botline, scale_map)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
	if not ok or not parser then
		return {}
	end

	parser:parse(true)

	local query_ok, query = pcall(vim.treesitter.query.parse, "markdown", "(atx_heading) @heading")
	if not query_ok then
		return {}
	end

	local trees = parser:trees()
	if not trees or not trees[1] then
		return {}
	end

	local root = trees[1]:root()
	local headings = {}

	for id, node in query:iter_captures(root, buf) do
		local name = query.captures[id]
		if name ~= "heading" then
			goto continue
		end

		local sr, sc, er, ec = node:range()

		-- Only process headings in or near the visible range
		if sr < (topline - 6) or sr > botline then
			goto continue
		end

		-- Get level from first child (atx_h1_marker, atx_h2_marker, etc.)
		local marker = node:child(0)
		if not marker then
			goto continue
		end

		local marker_text = vim.treesitter.get_node_text(marker, buf)
		local level = #marker_text -- count # characters

		-- Only handle levels we have scale mappings for
		if not scale_map[level] then
			goto continue
		end

		-- Extract heading text (skip markers + space)
		local line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1]
		if not line then
			goto continue
		end
		local heading_text = line:sub(#marker_text + 2) -- skip "# " or "## "

		table.insert(headings, {
			level = level,
			text = heading_text,
			start_row = sr,
			start_col = sc,
			end_row = er,
			end_col = ec,
			marker_end_col = #marker_text + 1,
		})

		::continue::
	end

	return headings
end

return M
