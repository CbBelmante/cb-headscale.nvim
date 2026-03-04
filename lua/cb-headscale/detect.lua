local M = {}

---@type boolean|nil
local supported = nil

--- Check if running inside a terminal multiplexer that blocks OSC 66
--- tmux supports allow-passthrough, so only Zellij is blocked
---@return boolean
function M.is_multiplexed()
	return vim.env.ZELLIJ ~= nil
		or vim.env.ZELLIJ_SESSION_NAME ~= nil
end

--- Check if the terminal supports OSC 66 text sizing
---@return boolean
function M.is_supported()
	if supported ~= nil then
		return supported
	end

	-- Multiplexers block OSC 66 passthrough
	if M.is_multiplexed() then
		supported = false
		return false
	end

	-- Not in Kitty at all
	if not vim.env.KITTY_PID and vim.env.TERM ~= "xterm-kitty" then
		supported = false
		return false
	end

	-- Check version via TERM_PROGRAM_VERSION
	local ver = vim.env.TERM_PROGRAM_VERSION
	if ver then
		local major, minor = ver:match("^(%d+)%.(%d+)")
		if major and minor then
			supported = tonumber(major) > 0 or tonumber(minor) >= 40
			return supported
		end
	end

	-- Fallback: query kitty binary
	local ok, result = pcall(vim.fn.system, "kitty --version 2>/dev/null")
	if ok and result then
		local major, minor = result:match("(%d+)%.(%d+)")
		if major and minor then
			supported = tonumber(major) > 0 or tonumber(minor) >= 40
			return supported
		end
	end

	supported = false
	return false
end

function M.reset()
	supported = nil
end

return M
