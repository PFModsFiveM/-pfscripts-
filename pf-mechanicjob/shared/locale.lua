Locale = {}
Locale.Phrases = {}
Locale.CurrentLocale = Config.Locale or 'en'

function Locale:t(str, vars)
    local phrase = self.Phrases[self.CurrentLocale] and self.Phrases[self.CurrentLocale][str] or str
    
    if vars then
        for k, v in pairs(vars) do
            phrase = phrase:gsub('{' .. k .. '}', tostring(v))
        end
    end
    
    return phrase
end

function Locale:Load(locale, phrases)
    self.Phrases[locale] = phrases
end

-- Shorthand
function L(str, vars)
    return Locale:t(str, vars)
end

-- Export for external use
_G.L = L
