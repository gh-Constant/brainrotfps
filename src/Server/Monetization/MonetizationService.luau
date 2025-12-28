--!strict
--[[
    MonetizationService
    Handles all server-side monetization logic (GamePasses, DevProducts).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local ProductConfig = require(Shared:WaitForChild("Monetization"):WaitForChild("ProductConfig"))
local Signal = require(Rojo.Packages.signal)

-- Module
local MonetizationService = {}
MonetizationService.OnGamePassPurchased = Signal.new()

-- Constants
local PURCHASE_HISTORY_DS = "PurchaseHistory_v1"

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Handles Developer Product pirchases.
]]
local function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
    local userId = receiptInfo.PlayerId
    local productId = receiptInfo.ProductId
    
    local player = Players:GetPlayerByUserId(userId)
    
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Find which product this is
    -- TODO: Implement DevProduct logic when we have DevProducts
    -- for key, product in pairs(ProductConfig.DevProducts) do
    --     if product.Id == productId then
    --          -- Grant product
    --          return Enum.ProductPurchaseDecision.PurchaseGranted
    --     end
    -- end
    
    -- If we don't recognize the product
    warn(string.format("[MonetizationService] Unknown product ID: %d", productId))
    return Enum.ProductPurchaseDecision.NotProcessedYet
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function MonetizationService.Init()
    -- Set the ProcessReceipt callback calling it only ONCE
    MarketplaceService.ProcessReceipt = processReceipt
    
    -- Listen for GamePass purchases
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
        if wasPurchased then
            print(string.format("[MonetizationService] %s purchased GamePass %d", player.Name, passId))
            MonetizationService.OnGamePassPurchased:Fire(player, passId)
        end
    end)
    
    print("[MonetizationService] Initialized!")
end

--[[
    Checks if a player owns a game pass, safe wrapper + caching (internal Roblox caching).
    
    @param player Player
    @param passId number
    @return boolean
]]
function MonetizationService.PerformPassCheck(player: Player, passId: number): boolean
    local RETRY_COUNT = 3
    local RETRY_DELAY = 1

    for i = 1, RETRY_COUNT do
        local success, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
        end)
        
        if success then
            return owns
        else
            warn(string.format("[MonetizationService] Failed to check pass %d for %s (Attempt %d/%d)", passId, player.Name, i, RETRY_COUNT))
            if i < RETRY_COUNT then
                task.wait(RETRY_DELAY)
            end
        end
    end
    
    return false
end

return MonetizationService
