--!strict
local Separator = {}

function Separator.Mount(instance: GuiObject, item: any, props: any)
	if props.Height then
		instance.Size = UDim2.new(instance.Size.X.Scale, instance.Size.X.Offset, 0, props.Height)
	end
end

return Separator
