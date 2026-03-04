if vim.g.loaded_cb_headscale then
	return
end
vim.g.loaded_cb_headscale = true

vim.api.nvim_create_user_command("CbHeadscaleEnable", function()
	require("cb-headscale").enable()
end, { desc = "Enable cb-headscale heading scaling" })

vim.api.nvim_create_user_command("CbHeadscaleDisable", function()
	require("cb-headscale").disable()
end, { desc = "Disable cb-headscale heading scaling" })

vim.api.nvim_create_user_command("CbHeadscaleToggle", function()
	require("cb-headscale").toggle()
end, { desc = "Toggle cb-headscale heading scaling" })
