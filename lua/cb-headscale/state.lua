local M = {}

---@class RenderedHeading
---@field heading HeadingInfo
---@field screen_row integer
---@field screen_col integer
---@field scale integer

---@class BufferState
---@field headings RenderedHeading[]
---@field is_active boolean

---@type table<integer, table<integer, BufferState>>  win_id -> buf_id -> state
M.windows = {}

--- Get or create state for a window/buffer pair
---@param win integer
---@param buf integer
---@return BufferState
function M.get(win, buf)
	if not M.windows[win] then
		M.windows[win] = {}
	end
	if not M.windows[win][buf] then
		M.windows[win][buf] = {
			headings = {},
			is_active = true,
		}
	end
	return M.windows[win][buf]
end

--- Clear state for a window
---@param win integer
function M.clear_window(win)
	M.windows[win] = nil
end

--- Clear state for a buffer across all windows
---@param buf integer
function M.clear_buffer(buf)
	for win, bufs in pairs(M.windows) do
		bufs[buf] = nil
	end
end

--- Clear all state
function M.clear_all()
	M.windows = {}
end

return M
