local config = require("cb-headscale.config")
local detect = require("cb-headscale.detect")
local renderer = require("cb-headscale.renderer")
local state = require("cb-headscale.state")

local M = {}

local group = vim.api.nvim_create_augroup("CbHeadscale", { clear = true })
local attached_buffers = {}

--- Attach to a markdown buffer and start rendering scaled headings
---@param buf integer
function M.attach(buf)
	if attached_buffers[buf] then
		return
	end
	attached_buffers[buf] = true

	-- LIGHTWEIGHT: cursor movement — only toggles overlay, no treesitter
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = buf,
		callback = function()
			if not config.current.enabled then
				return
			end
			local win = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_buf(win) == buf then
				renderer.update_cursor(win, buf)
			end
		end,
	})

	-- HEAVY (debounced): structural changes — full treesitter parse
	vim.api.nvim_create_autocmd({ "TextChanged", "WinScrolled" }, {
		group = group,
		buffer = buf,
		callback = function()
			if not config.current.enabled then
				return
			end
			local win = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_buf(win) == buf then
				renderer.render_debounced(win, buf)
			end
		end,
	})

	-- HEAVY (immediate): idle or entering buffer — safe to do full render
	vim.api.nvim_create_autocmd({ "CursorHold", "BufWinEnter" }, {
		group = group,
		buffer = buf,
		callback = function()
			if not config.current.enabled then
				return
			end
			local win = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_buf(win) == buf then
				renderer.render(win, buf)
			end
		end,
	})

	-- Clear OSC 66 when leaving the markdown buffer
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				renderer.clear(win, buf)
			end
		end,
	})

	-- Re-render when coming back to the buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		buffer = buf,
		callback = function()
			if not config.current.enabled then
				return
			end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				local win = vim.api.nvim_get_current_win()
				if vim.api.nvim_win_get_buf(win) == buf then
					renderer.render(win, buf)
				end
			end)
		end,
	})

	-- Initial render
	vim.schedule(function()
		local win = vim.api.nvim_get_current_win()
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_buf(win) == buf then
			renderer.render(win, buf)
		end
	end)
end

--- Setup the plugin
---@param opts table|nil
function M.setup(opts)
	config.setup(opts)

	if detect.is_multiplexed() then
		if config.current.debug then
			vim.notify("[cb-headscale] Zellij/tmux detectado — OSC 66 nao suportado (passthrough pendente)", vim.log.levels.WARN)
		end
		return
	end

	if not detect.is_supported() then
		if config.current.debug then
			vim.notify("[cb-headscale] Kitty >= 0.40 nao detectado — plugin desativado", vim.log.levels.WARN)
		end
		return
	end

	-- Auto-attach to markdown buffers
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "markdown",
		callback = function(args)
			M.attach(args.buf)
		end,
	})

	-- Attach to current buffer if already markdown
	if vim.bo.filetype == "markdown" then
		M.attach(vim.api.nvim_get_current_buf())
	end

	-- Handle window resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			for buf, _ in pairs(attached_buffers) do
				if vim.api.nvim_buf_is_valid(buf) then
					for _, win in ipairs(vim.fn.win_findbuf(buf)) do
						renderer.render(win, buf)
					end
				end
			end
		end,
	})

	-- Clean up on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			state.clear_all()
		end,
	})
end

function M.enable()
	config.current.enabled = true
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	if attached_buffers[buf] then
		renderer.render(win, buf)
	end
end

function M.disable()
	config.current.enabled = false
	for buf, _ in pairs(attached_buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				renderer.clear(win, buf)
			end
		end
	end
end

function M.toggle()
	if config.current.enabled then
		M.disable()
	else
		M.enable()
	end
end

return M
