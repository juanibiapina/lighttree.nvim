.PHONY: format
format:
	stylua --glob '*.lua' --glob '!defaults.lua' .
