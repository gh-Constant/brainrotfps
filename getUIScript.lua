local Selection = game:GetService("Selection")

local function round(num)
	return math.round(num * 1000) / 1000
end

local function formatValue(val)
	if typeof(val) == "Color3" then
		return string.format("Color3.fromRGB(%d, %d, %d)", math.round(val.R*255), math.round(val.G*255), math.round(val.B*255))
	elseif typeof(val) == "Vector2" then
		return string.format("Vector2.new(%s, %s)", round(val.X), round(val.Y))
	elseif typeof(val) == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)", round(val.X), round(val.Y), round(val.Z))
	elseif typeof(val) == "UDim2" then
		return string.format("UDim2.new(%s, %d, %s, %d)", round(val.X.Scale), val.X.Offset, round(val.Y.Scale), val.Y.Offset)
	elseif typeof(val) == "UDim" then
		return string.format("UDim.new(%s, %d)", round(val.Scale), val.Offset)
	elseif typeof(val) == "Rect" then
		return string.format("Rect.new(%d, %d, %d, %d)", val.Min.X, val.Min.Y, val.Max.X, val.Max.Y)
	elseif typeof(val) == "string" then
		return string.format("%q", val)
	elseif typeof(val) == "number" then
		return tostring(round(val))
	elseif typeof(val) == "boolean" then
		return tostring(val)
	elseif typeof(val) == "EnumItem" then
		return tostring(val)
	elseif typeof(val) == "ColorSequence" then
		local kpStr = {}
		for _, kp in ipairs(val.Keypoints) do
			table.insert(kpStr, string.format("ColorSequenceKeypoint.new(%s, %s)", round(kp.Time), formatValue(kp.Value)))
		end
		return string.format("ColorSequence.new({%s})", table.concat(kpStr, ", "))
	elseif typeof(val) == "NumberSequence" then
		local kpStr = {}
		for _, kp in ipairs(val.Keypoints) do
			table.insert(kpStr, string.format("NumberSequenceKeypoint.new(%s, %s, %s)", round(kp.Time), round(kp.Value), round(kp.Envelope)))
		end
		return string.format("NumberSequence.new({%s})", table.concat(kpStr, ", "))
	end
	return nil
end

local propertiesToCheck = {
	"Name", "Visible", "ZIndex", "LayoutOrder",
	"Position", "Size", "AnchorPoint", "Rotation", "BackgroundColor3", "BackgroundTransparency",
	"BorderColor3", "BorderSizePixel", "BorderMode",
	"ClipsDescendants", "AutoLocalize",
	
	-- Text
	"Text", "TextColor3", "TextTransparency", "TextSize", "Font", "TextXAlignment", "TextYAlignment", 
	"TextWrapped", "TextScaled", "RichText", "TextStrokeColor3", "TextStrokeTransparency", "PlaceholderText", "PlaceholderColor3",
	
	-- Image
	"Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale", "TileSize", "ResampleMode", "ImageRectOffset", "ImageRectSize",
	
	-- Scrolling
	"CanvasSize", "CanvasPosition", "ScrollBarImageColor3", "ScrollBarThickness", "ScrollBarImageTransparency", "ScrollingDirection", "ElasticBehavior",
    "HorizontalScrollBarInset", "VerticalScrollBarInset", "VerticalScrollBarPosition",
	
	-- UIStroke
	"ApplyStrokeMode", "Color", "LineJoinMode", "Thickness", "Transparency",
	
	-- UICorner
	"CornerRadius",
	
	-- UIGradient
	"Enabled", "Offset", "Rotation", -- Color and Transparency checked manually as Sequences
	
	-- UIListLayout/UIGridLayout
	"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", 
	"CellPadding", "CellSize", "StartCorner", "FillDirectionMaxCells",
	
	-- UIPadding
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
    
    -- UIScale
    "Scale",
    
    -- UIAspectRatioConstraint
    "AspectRatio", "AspectType", "DominantAxis"
}

-- Special handling for properties that are sequences or require checks
local function getProperties(obj)
	local props = {}
	
    -- Standard checks
	for _, propName in ipairs(propertiesToCheck) do
		pcall(function()
			local val = obj[propName]
			-- Basic check to skip defaults (very rough optimization)
			if val ~= nil then
				props[propName] = val
			end
		end)
	end
    
    -- Sequences (Color/Transparency for Gradient)
    if obj:IsA("UIGradient") then
        props["Color"] = obj.Color
        props["Transparency"] = obj.Transparency
    end
    
	return props
end

local output = {}
local function append(str)
	table.insert(output, str)
end

local function serialize(obj, parentVarName)
    local varName = obj.Name:gsub("[^%w_]", "") .. "_" .. math.random(1000,9999)
    if not obj.Name:find("^%a") then varName = "Obj" .. varName end
    
    append(string.format("local %s = Instance.new(%q)", varName, obj.ClassName))
    
    local props = getProperties(obj)
    for prop, val in pairs(props) do
        local formatted = formatValue(val)
        if formatted then
             -- Simple heuristic to skip "default-ish" values to reduce bloat
             -- This is manual and not exhaustive
             if prop == "Name" and val == obj.ClassName then formatted = nil end
             if prop == "Visible" and val == true then formatted = nil end
             -- if prop == "BackgroundTransparency" and val == 0 and obj:IsA("Frame") == false then formatted = nil end
             
             if formatted then
                append(string.format("%s.%s = %s", varName, prop, formatted))
             end
        end
    end
    
    if parentVarName then
        append(string.format("%s.Parent = %s", varName, parentVarName))
    end
    append("") -- spacing
    
    for _, child in ipairs(obj:GetChildren()) do
        serialize(child, varName)
    end
    
    return varName
end

local targets = Selection:Get()
if #targets == 0 then
    warn("Select a UI element to serialize")
    return
end

local target = targets[1]
append("-- Serialized UI for: " .. target.Name)
append("return function(targetParent)")
append("")

local rootVar = serialize(target, nil)
append(string.format("%s.Parent = targetParent", rootVar))
append(string.format("return %s", rootVar))

append("end")

local result = table.concat(output, "\n")

-- Create the result script
local scriptObj = Instance.new("ModuleScript")
scriptObj.Name = "Serialized_" .. target.Name
scriptObj.Source = result
scriptObj.Parent = target

print("Serialization complete! Check " .. scriptObj.Name .. " inside " .. target.Name)
