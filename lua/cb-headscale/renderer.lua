local config = require("cb-headscale.config")
local detect = require("cb-headscale.detect")
local parser = require("cb-headscale.parser")
local state = require("cb-headscale.state")
local terminal = require("cb-headscale.terminal")

local M = {}

local ns_space = vim.api.nvim_create_namespace("cb-headscale-space")
local ns_overlay = vim.api.nvim_create_namespace("cb-headscale-overlay")

local uv = vim.uv or vim.loop
local osc_timer = uv.new_timer()
local render_timer = uv.new_timer()
local OSC_DEBOUNCE_MS = 50
local RENDER_DEBOUNCE_MS = 100

-- Per-buffer caches
local space_fingerprints = {} ---@type table<integer, string>
local cached_headings = {} ---@type table<integer, HeadingInfo[]>
local last_cursor_row = {} ---@type table<integer, integer|nil>

local function screen_pos(win, buf_row)
	local pos = vim.fn.screenpos(win, buf_row + 1, 1)
	return pos.row, pos.col
end

local function build_fingerprint(headings, scale_map)
	local parts = {}
	for _, h in ipairs(headings) do
		local scale = scale_map[h.level]
		if scale and scale > 1 then
			parts[#parts + 1] = h.start_row .. ":" .. scale
		end
	end
	return table.concat(parts, ",")
end

local function update_space_extmarks(buf, headings, scale_map)
	local fp = build_fingerprint(headings, scale_map)
	if space_fingerprints[buf] == fp then
		return
	end
	space_fingerprints[buf] = fp

	vim.api.nvim_buf_clear_namespace(buf, ns_space, 0, -1)

	for _, h in ipairs(headings) do
		local scale = scale_map[h.level]
		if not scale or scale <= 1 then
			goto continue
		end
		local extra_lines = scale - 1
		if extra_lines > 0 then
			local virt_lines = {}
			for _ = 1, extra_lines do
				virt_lines[#virt_lines + 1] = { { "", "" } }
			end
			pcall(vim.api.nvim_buf_set_extmark, buf, ns_space, h.start_row, 0, {
				virt_lines = virt_lines,
				virt_lines_above = false,
				strict = false,
			})
		end
		::continue::
	end
end

local function update_overlay_extmarks(buf, headings, scale_map, cursor_row)
	vim.api.nvim_buf_clear_namespace(buf, ns_overlay, 0, -1)

	for _, h in ipairs(headings) do
		local scale = scale_map[h.level]
		if not scale or scale <= 1 then
			goto continue
		end
		if cursor_row and cursor_row == h.start_row then
			goto continue
		end
		local line = vim.api.nvim_buf_get_lines(buf, h.start_row, h.start_row + 1, false)[1]
		if line then
			local blank = string.rep(" ", vim.fn.strdisplaywidth(line))
			pcall(vim.api.nvim_buf_set_extmark, buf, ns_overlay, h.start_row, 0, {
				virt_text = { { blank, "" } },
				virt_text_pos = "overlay",
				strict = false,
			})
		end
		::continue::
	end
end

local function emit_osc66(win, headings, cursor_row)
	local cfg = config.current
	local total_rows = vim.o.lines

	terminal.sync_start()
	terminal.save_cursor()

	for _, h in ipairs(headings) do
		local scale = cfg.scale_map[h.level]
		if not scale or scale <= 1 then
			goto continue
		end
		if cfg.anti_conceal and cursor_row and cursor_row == h.start_row then
			goto continue
		end
		local srow, scol = screen_pos(win, h.start_row)
		if srow == 0 and scol == 0 then
			goto continue
		end
		if srow + scale - 1 > total_rows - 2 then
			goto continue
		end
		local term_cols = vim.o.columns
		local available = term_cols - scol + 1
		local max_chars = math.floor(available / scale)
		local text = h.text
		if #text > max_chars and max_chars > 3 then
			text = text:sub(1, max_chars - 1) .. "…"
		end
		terminal.move_cursor(srow, scol)
		terminal.write_osc66(text, {
			s = scale,
			w = 0,
			v = cfg.valign,
			h = cfg.halign,
		})
		::continue::
	end

	terminal.restore_cursor()
	terminal.sync_end()
end

local function has_floating_windows()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local wincfg = vim.api.nvim_win_get_config(win)
		if wincfg.relative and wincfg.relative ~= "" then
			return true
		end
	end
	return false
end

local function schedule_osc66(win, buf, headings, cursor_row)
	osc_timer:stop()
	osc_timer:start(OSC_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
		if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if has_floating_windows() then
			return
		end
		emit_osc66(win, headings, cursor_row)
	end))
end

--- Lightweight cursor update — NO treesitter, uses cached headings.
--- Only toggles overlay extmarks + debounced OSC 66.
--- Called on CursorMoved.
---@param win integer
---@param buf integer
function M.update_cursor(win, buf)
	local cfg = config.current
	if not cfg.enabled or not detect.is_supported() then
		return
	end
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if has_floating_windows() then
		return
	end

	local headings = cached_headings[buf]
	if not headings then
		return
	end

	local cursor_row = nil
	if cfg.anti_conceal then
		local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
		if ok then
			cursor_row = cursor[1] - 1
		end
	end

	-- Skip if cursor didn't change row
	if cursor_row == last_cursor_row[buf] then
		return
	end
	last_cursor_row[buf] = cursor_row

	-- Only update overlays (cheap, no content shift)
	update_overlay_extmarks(buf, headings, cfg.scale_map, cursor_row)

	-- Debounced OSC 66
	schedule_osc66(win, buf, headings, cursor_row)
end

--- Full render — treesitter parse + space + overlay + OSC 66.
--- Called on TextChanged, WinScrolled, BufWinEnter, CursorHold.
---@param win integer
---@param buf integer
function M.render(win, buf)
	local cfg = config.current
	if not cfg.enabled or not detect.is_supported() then
		return
	end
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if has_floating_windows() then
		vim.api.nvim_buf_clear_namespace(buf, ns_overlay, 0, -1)
		vim.api.nvim_buf_clear_namespace(buf, ns_space, 0, -1)
		space_fingerprints[buf] = nil
		cached_headings[buf] = nil
		osc_timer:stop()
		return
	end
	if vim.api.nvim_get_current_win() ~= win then
		return
	end

	local wininfo = vim.fn.getwininfo(win)
	if not wininfo or not wininfo[1] then
		return
	end
	local topline = wininfo[1].topline
	local botline = wininfo[1].botline

	local headings = parser.get_headings(buf, topline, botline, cfg.scale_map)
	cached_headings[buf] = headings

	local cursor_row = nil
	if cfg.anti_conceal then
		local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
		if ok then
			cursor_row = cursor[1] - 1
		end
	end
	last_cursor_row[buf] = cursor_row

	update_space_extmarks(buf, headings, cfg.scale_map)
	update_overlay_extmarks(buf, headings, cfg.scale_map, cursor_row)
	schedule_osc66(win, buf, headings, cursor_row)

	local buf_state = state.get(win, buf)
	buf_state.headings = headings
end

--- Debounced render — for events that fire rapidly (TextChanged, WinScrolled)
---@param win integer
---@param buf integer
function M.render_debounced(win, buf)
	render_timer:stop()
	render_timer:start(RENDER_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
		M.render(win, buf)
	end))
end

--- Clear all rendered headings for a window/buffer
---@param win integer
---@param buf integer
function M.clear(win, buf)
	osc_timer:stop()
	render_timer:stop()
	pcall(vim.api.nvim_buf_clear_namespace, buf, ns_space, 0, -1)
	pcall(vim.api.nvim_buf_clear_namespace, buf, ns_overlay, 0, -1)
	space_fingerprints[buf] = nil
	cached_headings[buf] = nil
	last_cursor_row[buf] = nil
	state.clear_window(win)
	vim.schedule(function()
		vim.cmd("redraw!")
	end)
end

return M
