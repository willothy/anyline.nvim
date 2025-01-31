local M = {}

local cache = require('anyline.cache')
local markager = require('anyline.markager')
local utils = require('anyline.utils')
local ani_manager = require('anyline.animation_manager')

local function current_indentation(bufnr, line, col)
	local indents = cache.get_cache(bufnr).lines[line]
	if indents == nil then return -1 end

	local column

	local tabs = vim.bo[bufnr].expandtab == false

	for _, indent in ipairs(indents) do
		local offset = tabs and vim.bo[bufnr].tabstop - 1 or 1
		if col + offset > indent then column = indent end
	end

	return column or -1
end

---@alias context { startln: number, endln: number, column: number, bufnr: number, winid: number }

local function find_range(bufnr, cursor, column)
	local ranges = cache.buffer_caches[bufnr].line_ranges[column]
	if not ranges then return end

	for _, line_pair in ipairs(ranges) do
		local startln, endln = unpack(line_pair)
		if cursor >= startln and cursor <= endln then --
			return startln, endln
		end
	end
end

---@return context | nil
function M.get_context_info(bufnr)
	local winid = vim.api.nvim_get_current_win()
	local cursor, col = unpack(vim.api.nvim_win_get_cursor(winid))
	cursor = cursor - 1

	local column = current_indentation(bufnr, cursor, col)
	local line_len = math.huge
	if vim.api.nvim_buf_is_valid(bufnr) then
		line_len = #vim.api.nvim_buf_get_lines(bufnr, cursor, cursor + 1, true)[1]
	end
	local next = current_indentation(bufnr, cursor + 1, math.min(col, line_len))

	if not column and not next then return end

	-- include context when cursor is on start of context (not inside indentation yet)
	if next > column then
		column = next
		cursor = cursor + 1
	end

	column = column - utils.get_scroll_offset()

	if column < 0 then return end

	local ranges = cache.buffer_caches[bufnr].line_ranges[column]

	if not ranges then return end
	local startln, endln = find_range(bufnr, cursor, column)
	if startln then
		return {
			startln = startln,
			endln = endln,
			column = column,
			bufnr = bufnr,
			winid = winid,
		}
	end
end

---@param ctx1 context | nil
---@param ctx2 context | nil
function M.is_same_context(ctx1, ctx2)
	ctx2 = ctx2 or M.current_ctx
	if not ctx1 or not ctx2 then return end
	--stylua: ignore
	if ctx1.column  == ctx2.column and
	   ctx1.startln == ctx2.startln and
	   ctx1.endln   == ctx2.endln and
	   ctx1.bufnr   == ctx2.bufnr and
	   ctx1.winid   == ctx2.winid
	then return true end
end

local function set_context(bufnr, ctx)
	local marks = markager.context_range(bufnr, ctx.startln, ctx.endln, ctx.column)
	for _, mark in ipairs(marks) do
		markager.set_extmark(
			ctx.bufnr,
			mark.row,
			mark.column,
			'AnyLineContext',
			nil,
			{ priority = mark.opts.priority + 1, id = mark.id }
		)
	end
end

function M.hide_context(bufnr, ctx, animation)
	ctx = ctx or M.current_ctx

	animation = animation or set_context

	if ctx then
		ani_manager.cancel_animation(ctx)
		vim.schedule(function()
			local timers = animation(bufnr, ctx)
			ani_manager.add_animation(ctx, timers)
		end)
	end
end

function M.show_context(bufnr, ctx, animation)
	ctx = ctx or M.get_context_info(bufnr)
	if not ctx then return end

	animation = animation or set_context

	ani_manager.cancel_animation(ctx)

	vim.schedule(function()
		local timers = animation(bufnr, ctx)
		ani_manager.add_animation(ctx, timers)
	end)
end

function M.update_context(bufnr, show_animation, hide_animation)
	local ctx = M.get_context_info(bufnr)
	if M.is_same_context(ctx, M.current_ctx) then return end

	if
		M.current_ctx
		and not M.is_same_context(ctx, M.current_ctx)
		and M.current_ctx.winid == vim.api.nvim_get_current_win()
	then
		M.hide_context(bufnr, M.current_ctx, hide_animation)
	end

	M.current_ctx = ctx
	if not ctx then return end

	M.show_context(bufnr, ctx, show_animation)
end

return M
