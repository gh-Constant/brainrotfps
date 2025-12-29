--!strict
local Separator = {}

function Separator.Mount(instance: GuiObject, item: any, props: any)
    -- Separator is usually static, but we can support custom width/color props if needed
    -- For now, it just sits there.
    if props.Height then
        instance.Size = UDim2.new(instance.Size.X.Scale, instance.Size.X.Offset, 0, props.Height)
    end
end

return Separator
