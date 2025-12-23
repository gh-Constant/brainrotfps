--[[
NOTICE
Copyright (c) 2019 Andrew Bereza
Provided for public use in educational, recreational or commercial purposes under the Apache 2 License.
Please include this copyright & permission notice in all copies or substantial portions of Miner's Haven source code
]]

local MoneyLib = {}


MoneyLib.Suffixes = {"k","M","B","T","qd","Qn","sx","Sp","O","N","de","Ud","DD","tdD","qdD","QnD","sxD","SpD","OcD","NvD","Vgn","UVg","DVg","TVg","qtV","QnV","SeV","SPG","OVG","NVG","TGN","UTG","DTG","tsTG","qtTG","QnTG","ssTG","SpTG","OcTG","NoTG","QdDR","uQDR","dQDR","tQDR","qdQDR","QnQDR","sxQDR","SpQDR","OQDDr","NQDDr","qQGNT","uQGNT","dQGNT","tQGNT","qdQGNT","QnQGNT","sxQGNT","SpQGNT", "OQQGNT","NQQGNT","SXGNTL"}                                              
--                                                  																																															^NEW     ^ 10e123
MoneyLib.CachedShorts = {}

function MoneyLib.HandleMoney(val)
	local num: number = tonumber(val) or 0
    if not num then return "0" end
	if num < 1000 then return tostring(math.floor(num)) end
	
    -- Calculate tier (log10 / 3)
	local digits = math.floor(math.log10(num))
	local tier = math.floor(digits / 3)
    
	if tier >= 1 then
        -- Check cache
		if MoneyLib.CachedShorts[tier] then
			local suffix = MoneyLib.Suffixes[tier]
			local shortValue = num / (10 ^ (tier * 3))
			return string.format("%.1f%s", shortValue, suffix)
		end
		
		local suffix = MoneyLib.Suffixes[tier]
		if suffix then
			local shortValue = num / (10 ^ (tier * 3))
			return string.format("%.1f%s", shortValue, suffix)
		else
            -- Fallback for extremely large numbers not in suffix list
			return string.format("%.1e", num)
		end
	else
		return tostring(math.floor(num))
	end
end

-- Alias
function MoneyLib.Format(val: number)
    return MoneyLib.HandleMoney(val)
end

return MoneyLib
