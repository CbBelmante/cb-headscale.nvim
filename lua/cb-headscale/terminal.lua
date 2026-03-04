local M = {}

local uv = vim.uv or vim.loop
local stdout = uv.new_tty(1, false)

--- Write raw bytes to the terminal
---@param data string
function M.write(data)
	if not data or data == "" then
		return
	end
	stdout:write(data)
end

--- Save cursor position
function M.save_cursor()
	M.write("\x1b[s")
end

--- Restore cursor position
function M.restore_cursor()
	M.write("\x1b[u")
end

--- Move cursor to absolute screen position (1-indexed)
---@param row integer
---@param col integer
function M.move_cursor(row, col)
	M.write(("\x1b[%d;%dH"):format(row, col))
end

--- Begin synchronized update (prevent flicker)
function M.sync_start()
	M.write("\x1b[?2026h")
end

--- End synchronized update
function M.sync_end()
	M.write("\x1b[?2026l")
end

--- Emit an OSC 66 text sizing sequence
---@param text string  The text to render at the given scale
---@param opts { s?: integer, w?: integer, v?: integer, h?: integer }
function M.write_osc66(text, opts)
	local parts = {}
	if opts.s and opts.s > 1 then
		table.insert(parts, "s=" .. opts.s)
	end
	if opts.w and opts.w > 0 then
		table.insert(parts, "w=" .. opts.w)
	end
	if opts.v and opts.v > 0 then
		table.insert(parts, "v=" .. opts.v)
	end
	if opts.h and opts.h > 0 then
		table.insert(parts, "h=" .. opts.h)
	end
	local metadata = table.concat(parts, ":")
	M.write("\x1b]66;" .. metadata .. ";" .. text .. "\x07")
end

return M
