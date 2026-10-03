local _, ns = ...

-- Localization for the settings panel. The English text is the key; a language
-- file (Locales/<locale>.lua) assigns translations for its client locale only.
-- Anything untranslated falls back to English. Chat commands and chat output
-- stay English.
--
--   local L = ns.L
--   o:Checkbox("key", L["English label"], L["English tooltip"])

ns.LOCALE = GetLocale()

local isEnglish = ns.LOCALE == "enUS" or ns.LOCALE == "enGB"

-- Keys looked up without a translation, for spotting gaps (tests check this).
ns.L_MISSING = {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		if not isEnglish then
			ns.L_MISSING[key] = true
		end
		return key
	end,
})
