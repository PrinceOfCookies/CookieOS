local function cmdPrompt(device)
	device.setTextColor(colors.white)
	cosUtils.resetScreen(device)

	device.write("Welcome to COS CMD Prompt")
	device.setCursorPos(1, 2)
	device.write("===================================================")
	device.setCursorPos(1, 3)
end

cmdPrompt(term)

