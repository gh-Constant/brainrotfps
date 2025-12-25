--[[
    ITEM CONFIG ATTRIBUTES
    Place on Configuration in: Config/Items/{ItemName}
    
    REQUIRED:
    - Type: "Tool" | "Consumable" | "Material" | "Ticket" | "Boost" | "Cosmetic"
    
    OPTIONAL:
    - Rarity: "Common" | "Uncommon" | "Epic" | "Legendary" | "Mythic" | "Secret" | "God"
    - Image: "rbxassetid://123456789"  (custom image, skips 3D)
    - ToolModel: "ToolModels" | "ViewModel" | "ToolIcon"
    
    TOOLMODEL OPTIONS:
    - nil (default)  → Uses Tool child for 3D viewport
    - "ToolModels"   → Uses Config/ToolModels/{name} for 3D
    - "ViewModel"    → Uses Blaster/ViewModels/{name}/Blaster for 3D
    - "ToolIcon"     → Uses Tool.TextureId as image (no 3D)
]]
return nil
