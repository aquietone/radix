local mq = require 'mq'
require 'ImGui'
local recipes = require 'recipes'

local meta = {version='0.3',name='radix'}

local openGUI, shouldDrawGUI = true, true

local ingredientsArray = {}
local invSlotContainers = {['Fletching Kit'] = true, ['Feir`Dal Fletching Kit'] = true, ['Jeweler\'s Kit'] = true, ['Mixing Bowl'] = true, ['Essence Fusion Chamber'] = true, ['Medicine Bag'] = true}

local ingredientFilter = ''
local filteredIngredients = {}
local useIngredientFilter = false
local function filterIngredients()
    filteredIngredients = {}
    for _,ingredient in pairs(ingredientsArray) do
        if ingredient.Name:lower():find(ingredientFilter:lower()) then
            table.insert(filteredIngredients, ingredient)
        end
    end
end


local ColumnID_Name = 1
local ColumnID_Location = 2
local ColumnID_SourceType = 3
local ColumnID_Zone = 4
local current_sort_specs = nil
local function CompareWithSortSpecs(a, b)
    for n = 1, current_sort_specs.SpecsCount, 1 do
        local sort_spec = current_sort_specs:Specs(n)
        local delta = 0

        local sortA = a.Name
        local sortB = b.Name
        if sort_spec.ColumnUserID == ColumnID_Name then
            sortA = a.Name
            sortB = b.Name
        elseif sort_spec.ColumnUserID == ColumnID_Location then
            sortA = a.Location
            sortB = b.Location
        elseif sort_spec.ColumnUserID == ColumnID_SourceType then
            sortA = a.SourceType
            sortB = b.SourceType
        elseif sort_spec.ColumnUserID == ColumnID_Zone then
            sortA = (a.Zone and a.Zone) or (a.SourceType ~= 'Vendor' and a.Location) or 'Temple of Marr'
            sortB = (b.Zone and b.Zone) or (b.SourceType ~= 'Vendor' and b.Location) or 'Temple of Marr'
        end
        if sortA < sortB then
            delta = -1
        elseif sortB < sortA then
            delta = 1
        else
            delta = 0
        end

        if delta ~= 0 then
            if sort_spec.SortDirection == ImGuiSortDirection.Ascending then
                return delta < 0
            end
            return delta > 0
        end
    end

    -- Always return a way to differentiate items.
    return a.Name < b.Name
end

local selectedTradeskill = nil
local selectedRecipe = nil
local thingsToCraft = {}
local buying = {
    Recipe = '',
    Qty = 1000,
    Status = false
}
local requesting = {
    Status = false
}
local crafting = {
    Status = false,
    StopAtTrivial = true,
    NumMade = 0,
    SuccessMessage = nil,
    FailedMessage = nil,
    DoSubcombines = false,
}
local selling = {
    Status = false
}
local function RecipeTreeNode(recipe, tradeskill, idx)
    if recipe.Trivial >= tradeskill + 50 then
        ImGui.PushStyleColor(ImGuiCol.Text, 1,0,0,1)
    elseif recipe.Trivial >= tradeskill + 10 then
        ImGui.PushStyleColor(ImGuiCol.Text, 1,1,0,1)
    elseif recipe.Trivial <= tradeskill then
        ImGui.PushStyleColor(ImGuiCol.Text, 0,1,0,1)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1,1,1,1)
    end
    local expanded = ImGui.TreeNode(('%s (Trivial: %s) (Qty: %s)###%s%s'):format(recipe.Recipe, recipe.Trivial, mq.TLO.FindItemCount('='..recipe.Recipe)(), recipe.Recipe, idx))
    ImGui.PopStyleColor()
    ImGui.SameLine()
    if ImGui.SmallButton('Select##'..recipe.Recipe..idx) then
        selectedRecipe = recipe
        crafting.FailedMessage = nil
        crafting.SuccessMessage = nil
    end
    if expanded then
        ImGui.Indent(15)
        for i,material in ipairs(recipe.Materials) do
            if recipes.Subcombines[material] then
                RecipeTreeNode(recipes.Subcombines[material], tradeskill, idx+i)
            else
                ImGui.Text('%s%s', material, recipes.Materials[material] and ' - ' .. recipes.Materials[material].Location or '')
                ImGui.SameLine()
                ImGui.TextColored(1,1,0,1,'(Qty: %s)', mq.TLO.FindItemCount('='..material)())
            end
        end
        ImGui.Unindent(15)
        ImGui.TreePop()
    end
end

local function drawSelectedRecipeBar(tradeskill)
    if selectedRecipe then
        ImGui.Text('Selected Recipe: ')
        ImGui.SameLine()
        ImGui.TextColored(1,1,0,1,'%s', selectedRecipe.Recipe)
        if not buying.Status and not requesting.Status and not crafting.Status and not selling.Status then
            if ImGui.Button('Craft') then
                if (tradeskill == 'Alchemy') and mq.TLO.Me.Skill(tradeskill)() == 0 then
                    crafting.Status = false
                    crafting.FailedMessage = 'Train at least 1 point in '..tradeskill..' first!'
                else
                    crafting.Status = true
                    crafting.OutOfMats = false
                    selectedTradeskill = selectedRecipe.Tradeskill or tradeskill
                    thingsToCraft = {}
                end
            end
            ImGui.SameLine()
            if ImGui.Button('Craft All') then
                if (tradeskill == 'Alchemy') and mq.TLO.Me.Skill(tradeskill)() == 0 then
                    crafting.Status = false
                    crafting.FailedMessage = 'Train at least 1 point in '..tradeskill..' first!'
                else
                    crafting.Status = true
                    crafting.OutOfMats = false
                    selectedTradeskill = selectedRecipe.Tradeskill or tradeskill
                    buying.Qty = -1
                    thingsToCraft = {}
                end
            end
            ImGui.SameLine()
            if ImGui.Button('Buy Mats') then
                buying.Status = true
            end
            ImGui.SameLine()
            if ImGui.Button('Request Mats') then
                requesting.Status = true
            end
            ImGui.SameLine()
            ImGui.PushItemWidth(120)
            buying.Qty = ImGui.InputInt('Qty', buying.Qty, 1, 10)
            ImGui.PopItemWidth()
            ImGui.SameLine()
            crafting.Destroy = ImGui.Checkbox('Destroy', crafting.Destroy)
            ImGui.SameLine()
            -- crafting.Fast = ImGui.Checkbox('Fast', crafting.Fast)
            -- ImGui.SameLine()
            crafting.StopAtTrivial = ImGui.Checkbox('Stop At Trivial', crafting.StopAtTrivial)
            ImGui.SameLine()
            crafting.DoSubcombines = ImGui.Checkbox('Craft Subcombines', crafting.DoSubcombines)
            ImGui.SameLine()
            if ImGui.Button('Sell') then
                selling.Status = true
            end
            ImGui.Text('Free Inventory: %s', mq.TLO.Me.FreeInventory())
            if crafting.FailedMessage then
                ImGui.TextColored(1, 0, 0, 1, '%s', crafting.FailedMessage)
            elseif crafting.SuccessMessage then
                ImGui.TextColored(0, 1, 0, 1, '%s', crafting.SuccessMessage)
            end
        else
            ImGui.Text('Free Inventory: %s', mq.TLO.Me.FreeInventory())
            ImGui.PushStyleColor(ImGuiCol.Text, 1,0,0,1)
            if ImGui.Button('Cancel') then
                crafting.Status, selling.Status, buying.Status = false, false, false
            end
            ImGui.PopStyleColor()
            ImGui.SameLine()
            if crafting.Status then
                ImGui.TextColored(0,1,0,1,'Crafting "%s" in progress... (%s/%s)', selectedRecipe.Recipe, crafting.NumMade, buying.Qty)
                -- ImGui.SameLine()
                -- crafting.Fast = ImGui.Checkbox('Fast', crafting.Fast)
            elseif selling.Status then
                ImGui.TextColored(0,1,0,1,'Selling "%s"', selectedRecipe.Recipe)
            else
                ImGui.TextColored(0,1,0,1,'Gathering Materials for "%s"...', selectedRecipe.Recipe)
            end
        end
    end
end

local function pushStyle()
    local t = {
        windowbg = ImVec4(.1, .1, .1, .9),
        bg = ImVec4(0, 0, 0, 1),
        hovered = ImVec4(.4, .4, .4, 1),
        active = ImVec4(.3, .3, .3, 1),
        button = ImVec4(.3, .3, .3, 1),
        text = ImVec4(1, 1, 1, 1),
    }
    ImGui.PushStyleColor(ImGuiCol.WindowBg, t.windowbg)
    ImGui.PushStyleColor(ImGuiCol.TitleBg, t.bg)
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, t.active)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, t.bg)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, t.hovered)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, t.active)
    ImGui.PushStyleColor(ImGuiCol.Button, t.button)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, t.hovered)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, t.active)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, t.bg)
    ImGui.PushStyleColor(ImGuiCol.Tab, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.TabActive, t.active)
    ImGui.PushStyleColor(ImGuiCol.TabHovered, t.hovered)
    ImGui.PushStyleColor(ImGuiCol.TabUnfocused, t.bg)
    ImGui.PushStyleColor(ImGuiCol.TabUnfocusedActive, t.hovered)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, t.text)
    ImGui.PushStyleColor(ImGuiCol.CheckMark, t.text)
    ImGui.PushStyleColor(ImGuiCol.Separator, t.hovered)

    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 10)
end

local function popStyles()
    ImGui.PopStyleColor(18)

    ImGui.PopStyleVar(1)
end

local tradeskills = {'Baking','Blacksmithing','Brewing','Fletching','Jewelry Making','Pottery','Tailoring','Alchemy'}
local function radixGUI()
    ImGui.SetNextWindowSize(ImVec2(800,500), ImGuiCond.FirstUseEver)
    pushStyle()
    openGUI, shouldDrawGUI = ImGui.Begin('Radix ('.. meta.version ..')###radixgui', openGUI, ImGuiWindowFlags.HorizontalScrollbar)
    if shouldDrawGUI then
        if ImGui.BeginTabBar('##TradeskillTabs') then
            for _,tradeskill in ipairs(tradeskills) do
                if tradeskill ~= 'Alchemy' or mq.TLO.Me.Class.ShortName() == 'SHM' then
                    local currentSkill = (tradeskill == 'Radix' and 300) or mq.TLO.Me.Skill(tradeskill)() or 0
                    ImGui.PushStyleColor(ImGuiCol.Text, currentSkill == 300 and 0 or 1, currentSkill == 300 and 1 or 0, 0, 1)
                    local label
                    if tradeskill == 'Radix' then
                        label = 'Radix'
                    elseif currentSkill == 300 then
                        label = tradeskill .. '##' .. tradeskill
                    else
                        label = ('%s (%s/300)###%s'):format(tradeskill, currentSkill, tradeskill)
                    end
                    local beginTab = ImGui.BeginTabItem(label)
                    ImGui.PopStyleColor()
                    if beginTab then
                        drawSelectedRecipeBar(tradeskill)
                        ImGui.Separator()
                        for i,recipe in ipairs(recipes[tradeskill]) do
                            ImGui.PushID(i)
                            RecipeTreeNode(recipe, currentSkill, 0)
                            ImGui.PopID()
                        end
                        ImGui.EndTabItem()
                    end
                end
            end
            if ImGui.BeginTabItem('Radix') then
                drawSelectedRecipeBar('Blacksmithing')
                ImGui.Separator()
                for _,recipe in ipairs(recipes.Radix) do
                    RecipeTreeNode(recipe, 300, 0)
                end
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem('Materials') then
                ImGui.PushItemWidth(300)
                local tmpIngredientFilter = ImGui.InputTextWithHint('##materialfilter', 'Search...', ingredientFilter)
                ImGui.PopItemWidth()
                if tmpIngredientFilter ~= ingredientFilter then
                    ingredientFilter = tmpIngredientFilter
                    filterIngredients()
                end
                if ingredientFilter ~= '' then useIngredientFilter = true else useIngredientFilter = false end
                local tmpIngredients = ingredientsArray
                if useIngredientFilter then tmpIngredients = filteredIngredients end

                if ImGui.BeginTable('Materials', 5, bit32.bor(ImGuiTableFlags.BordersInner, ImGuiTableFlags.RowBg, ImGuiTableFlags.Reorderable, ImGuiTableFlags.NoSavedSettings, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Sortable)) then
                    ImGui.TableSetupScrollFreeze(0, 1)
                    ImGui.TableSetupColumn('Material', bit32.bor(ImGuiTableColumnFlags.DefaultSort, ImGuiTableColumnFlags.WidthFixed), -1.0, ColumnID_Name)
                    ImGui.TableSetupColumn('Location', bit32.bor(ImGuiTableColumnFlags.WidthFixed), -1.0, ColumnID_Location)
                    ImGui.TableSetupColumn('Source', bit32.bor(ImGuiTableColumnFlags.WidthFixed), -1.0, ColumnID_SourceType)
                    ImGui.TableSetupColumn('Zone', bit32.bor(ImGuiTableColumnFlags.WidthFixed), -1.0, ColumnID_Zone)
                    ImGui.TableSetupColumn('Count', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed), -1.0, 0)
                    ImGui.TableHeadersRow()

                    local sort_specs = ImGui.TableGetSortSpecs()
                    if sort_specs then
                        if sort_specs.SpecsDirty then
                            current_sort_specs = sort_specs
                            table.sort(tmpIngredients, CompareWithSortSpecs)
                            current_sort_specs = nil
                            sort_specs.SpecsDirty = false
                        end
                    end

                    for _,ingredient in ipairs(tmpIngredients) do
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.Text(ingredient.Name)
                        ImGui.TableNextColumn()
                        ImGui.Text(ingredient.Location)
                        ImGui.TableNextColumn()
                        ImGui.Text(ingredient.SourceType)
                        ImGui.TableNextColumn()
                        ImGui.Text('%s', (ingredient.Zone and ingredient.Zone) or (ingredient.SourceType ~= 'Vendor' and ingredient.Location) or 'Temple of Marr')
                        ImGui.TableNextColumn()
                        ImGui.Text('%s', mq.TLO.FindItemCount('='..ingredient.Name)())
                    end
                    ImGui.EndTable()
                end
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end
    ImGui.End()
    popStyles()
    if not openGUI then
        mq.exit()
    end
end

local function goToVendor()
    if not mq.TLO.Target() then
        return false
    end
    local vendorName = mq.TLO.Target.CleanName()

    if mq.TLO.Target.Distance() > 15 then
        mq.cmdf('/nav spawn %s', vendorName)
        mq.delay(50)
        mq.delay(60000, function() return not mq.TLO.Navigation.Active() end)
    end
    return true
end

local function openVendor()
    mq.cmd('/nomodkey /click right target')
    mq.delay(1000, function() return mq.TLO.Window('MerchantWnd').Open() end)
    if not mq.TLO.Window('MerchantWnd').Open() then return false end
    mq.delay(5000, function() return mq.TLO.Merchant.ItemsReceived() end)
    return mq.TLO.Merchant.ItemsReceived()
end

local itemNoValue = nil
local function eventNovalue(line, item)
    itemNoValue = item
end
mq.event("Novalue", "#*#give you absolutely nothing for the #1#.#*#", eventNovalue)

local NEVER_SELL = {['Diamond Coin']=true, ['Celestial Crest']=true, ['Gold Coin']=true, ['Taelosian Symbols']=true, ['Planar Symbols']=true}
local function sellToVendor(itemToSell, bag, slot)
    if NEVER_SELL[itemToSell] then return end
    if mq.TLO.Window('MerchantWnd').Open() then
        if slot == nil or slot == -1 then
            mq.cmdf('/nomodkey /itemnotify %s leftmouseup', bag)
        else
            mq.cmdf('/nomodkey /itemnotify in pack%s %s leftmouseup', bag, slot)
        end
        mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == itemToSell() end)
        mq.cmd('/nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup')
        mq.doevents('eventNovalue')
        if itemNoValue == itemToSell then
            itemNoValue = nil
        end
        mq.delay(1000, function() return mq.TLO.Window("MerchantWnd/MW_Sell_Button")() ~= "TRUE" end)
    end
end

local function RestockItems(BuyItems, isTool)
    local rowNum = 0
    for itemName, qty in pairs(BuyItems) do
        rowNum = mq.TLO.Window("MerchantWnd/MW_ItemList").List('='..itemName,2)() or 0
        mq.delay(20)
        local haveCount = mq.TLO.FindItemCount('='..itemName)()
        while haveCount < qty do
            if isTool and haveCount >= 1 then return end
            local tmpQty = qty - haveCount
            if rowNum ~= 0 and tmpQty > 0 then
                mq.TLO.Window("MerchantWnd/MW_ItemList").Select(rowNum)()
                mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == itemName end)
                mq.TLO.Window("MerchantWnd/MW_Buy_Button").LeftMouseUp()
                mq.delay(500, function () return mq.TLO.Window("QuantityWnd").Open() end)
                if mq.TLO.Window("QuantityWnd").Open() then
                    mq.TLO.Window("QuantityWnd/QTYW_SliderInput").SetText(tostring(tmpQty))()
                    mq.delay(100, function () return mq.TLO.Window("QuantityWnd/QTYW_SliderInput").Text() == tostring(tmpQty) end)
                    mq.TLO.Window("QuantityWnd/QTYW_Accept_Button").LeftMouseUp()
                    mq.delay(100)
                end
            end
            mq.delay(500, function () return mq.TLO.FindItemCount('='..itemName)() >= qty end)
            haveCount = mq.TLO.FindItemCount('='..itemName)()
        end
    end
end

local function buy()
    if not selectedRecipe then buying.Status = false return end
    if invSlotContainers[selectedRecipe.Container] then
        if mq.TLO.FindItemCount('='..selectedRecipe.Container)() == 0 then
            local mat = recipes.Materials[selectedRecipe.Container]
            mq.cmdf('/mqt %s', mat.Location)
            if not mq.TLO.Window('MerchantWnd').Open() or mq.TLO.Window('MerchantWnd/MW_MerchantName').Text() ~= mat.Location then
                if mq.TLO.Window('MerchantWnd').Open() then mq.TLO.Window('MerchantWnd').DoClose() mq.delay(50) mq.cmdf('/mqt %s', mat.Location) end
                if not goToVendor() then return end
                if not openVendor() then return end
                mq.delay(500)
            end
            printf('Buying %s', selectedRecipe.Container)
            RestockItems({[selectedRecipe.Container]=1})
            mq.TLO.Window('MerchantWnd').DoClose() mq.delay(250)
        end
    end
    local numMatsNeeded = {}
    for _,mat in  ipairs(selectedRecipe.Materials) do
        numMatsNeeded[mat] = numMatsNeeded[mat] and numMatsNeeded[mat] + 1 or 1
    end
    for material,count in pairs(numMatsNeeded) do
    -- for _,material in ipairs(selectedRecipe.Materials) do
        local mat = recipes.Materials[material]
        if mat and mat.SourceType == 'Vendor' and (not mat.Zone or mq.TLO.Zone.ShortName() == mat.Zone) then
            if not buying.Status then return end
            mq.cmdf('/mqt %s', mat.Location)
            if not mq.TLO.Window('MerchantWnd').Open() or mq.TLO.Window('MerchantWnd/MW_MerchantName').Text() ~= mat.Location then
                if mq.TLO.Window('MerchantWnd').Open() then mq.TLO.Window('MerchantWnd').DoClose() mq.delay(50) mq.cmdf('/mqt %s', mat.Location) end
                if not goToVendor() then return end
                if not openVendor() then return end
                mq.delay(500)
            end
            printf('Buying %s %s(s)', buying.Qty*count, material)
            RestockItems({[material]=buying.Qty*count}, mat.Tool)
        end
    end
    if mq.TLO.Window('MerchantWnd').Open() then mq.TLO.Window('MerchantWnd').DoClose() end
    buying.Status = false
end

local function sell()
    if not selectedRecipe then selling.Status = false return end
    if not mq.TLO.Window('MerchantWnd').Open() then
        mq.cmd('/mqt merchant')
        if not goToVendor() then return end
        if not openVendor() then return end
    end
    for i = 1, 10 do
        local bagSlot = mq.TLO.InvSlot('pack' .. i).Item
        local containerSize = bagSlot.Container()

        if containerSize then
            for j = 1, containerSize do
                if not selling.Status then return end
                local item = bagSlot.Item(j)
                if item.ID() then
                    if item.Name() == selectedRecipe.Recipe then
                        sellToVendor(item, i, j)
                    end
                end
            end
        end
    end
    if mq.TLO.Window('MerchantWnd').Open() then mq.TLO.Window('MerchantWnd').DoClose() end
    selling.Status = false
end

local function split(input)
    local sep = "|"
    local t={}
    for str in string.gmatch(input, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function request()
    if not selectedRecipe then requesting.Status = false return end
    local peers = split(mq.TLO.DanNet.Peers())
    for _,peer in ipairs(peers) do
        if peer ~= mq.TLO.Me.CleanName() then
            for _,material in ipairs(selectedRecipe.Materials) do
                if not requesting.Status then return end
                printf('Requesting %s %s(s) from %s', buying.Qty, material, peer)
                mq.cmdf('/dex %s /giveit item pc %s "%s"', peer, mq.TLO.Me.CleanName(), material)
                mq.delay(1000)
            end
        end
    end
    requesting.Status = false
end

local function waitForCursor(time)
    mq.delay(time or 1000, function() return mq.TLO.Cursor() end)
end

local function waitForEmptyCursor(time)
    mq.delay(time or 1000, function() return not mq.TLO.Cursor() end)
end

local function clearCursor(num)
    local upper = num or 5
    for i=1,upper do
        waitForCursor(100)
        if mq.TLO.Cursor() then
            if crafting.Destroy and selectedRecipe and (mq.TLO.Cursor.Name() == selectedRecipe.OutputName or mq.TLO.Cursor.Name() == selectedRecipe.Recipe) then
                printf('Destroying cursor item: %s', selectedRecipe.OutputName and selectedRecipe.OutputName or selectedRecipe.Recipe)
                mq.cmd('/destroy')
            else
                mq.cmd('/autoinv')
            end
            waitForEmptyCursor(100)
        end
    end
end

local function findOpenSlot(skip_slot)
    for i=23,32 do
        if i ~= skip_slot then
            local inv_slot = mq.TLO.Me.Inventory(i)
            if inv_slot.Container() and inv_slot.Container() - inv_slot.Items() > 0 then
                for j=1,inv_slot.Container() do
                    if not inv_slot.Item(j)() then return ('in Pack%s %s'):format(i-22, j) end
                end
            end
        end
    end
end

local tempStopAtTriv = false
local function shouldCraft()
    if not selectedRecipe then printf('No recipe selected') return false end
    -- if selectedTradeskill and selectedRecipe.Trivial <= mq.TLO.Me.Skill(selectedTradeskill)() then printf('Skill already above trivial') return false end
    if invSlotContainers[selectedRecipe.Container] and (mq.TLO.FindItemCount('='..selectedRecipe.Container)() == 0 or mq.TLO.FindItem('='..selectedRecipe.Container).ItemSlot2() ~= -1) then
        printf('Recipe requires container in top level inventory slot: %s', selectedRecipe.Container)
        crafting.FailedMessage = ('Recipe requires container in top level inventory slot: %s'):format(selectedRecipe.Container)
        return false
    end
    local numMatsNeeded = {}
    for _,mat in  ipairs(selectedRecipe.Materials) do
        numMatsNeeded[mat] = numMatsNeeded[mat] and numMatsNeeded[mat] + 1 or 1
    end
    local maxCombines = 1000
    for mat,count in pairs(numMatsNeeded) do
        local matOrSubcombine = nil
        if recipes.Subcombines[mat] then
            matOrSubcombine = recipes.Subcombines[mat]
        elseif recipes.Materials[mat] then
            matOrSubcombine = recipes.Materials[mat]
        else
            printf('Unknown component: %s', mat)
            crafting.FailedMessage = ('Unknown component: %s'):format(mat)
            return false
        end
        if matOrSubcombine.Tool then
            if mq.TLO.FindItemCount('='..mat)() == 0 then
                printf('Missing tool: %s', mat)
                crafting.FailedMessage = ('Missing tool: %s'):format(mat)
                return false
            end
        else
            if buying.Qty == -1 then
                local numCombines = mq.TLO.FindItemCount('='..mat)() / count
                maxCombines = math.min(numCombines, maxCombines)
            elseif mq.TLO.FindItemCount('='..mat)() < (buying.Qty*count) then
                if crafting.DoSubcombines and recipes.Subcombines[mat] then
                    table.insert(thingsToCraft, selectedRecipe)
                    tempStopAtTriv = tempStopAtTriv or crafting.StopAtTrivial
                    crafting.StopAtTrivial = false
                    local tmpSelected = selectedRecipe
                    selectedRecipe = recipes.Subcombines[mat]
                    if not shouldCraft() then
                        printf('Insufficient materials: %s', mat)
                        crafting.FailedMessage = ('Insufficient materials: %s'):format(mat)
                        selectedRecipe = tmpSelected
                        return false
                    end
                else
                    printf('Insufficient materials: %s', mat)
                    crafting.FailedMessage = ('Insufficient materials: %s'):format(mat)
                    return false
                end
            end
        end
    end
    if maxCombines == 0 then buying.Qty = 1 return false end
    if buying.Qty == -1 then buying.Qty = maxCombines or 1 end
    crafting.FailedMessage = nil
    return true
end

local function craftInExperimental(pack)
    if not selectedRecipe then return end
    if not mq.TLO.Window(pack).Open() and mq.TLO.Window('TradeskillWnd').Open() then
        mq.cmd('/notify TradeskillWnd COMBW_ExperimentButton leftmouseup')
    end
    -- do combines
    printf('Crafting items')
    mq.cmdf('/keypress OPEN_INV_BAGS')
    mq.delay(500)
    crafting.NumMade = 0
    while crafting.NumMade < buying.Qty do
        if not crafting.Status then return end
        if crafting.StopAtTrivial and (mq.TLO.Me.Skill(selectedTradeskill or '')() >= selectedRecipe.Trivial or mq.TLO.Me.Skill(selectedTradeskill or '')() == 300) then
            crafting.SuccessMessage = 'Reached trivial for recipe!'
            return
        end
        if mq.TLO.Me.FreeInventory() == 0 then
            crafting.FailedMessage = 'Inventory is full!'
            return
        end
        clearCursor(#selectedRecipe.Materials)

        -- Fill the container with materials
        for i,mat in ipairs(selectedRecipe.Materials) do
            if mq.TLO.Cursor() then clearCursor() end
            mq.cmdf('/nomodkey /ctrlkey /itemnotify "%s" leftmouseup', mat)
            waitForCursor()
            if (mq.TLO.Cursor.Stack() or 1) > 1 then
                clearCursor()
                mq.cmdf('/nomodkey /ctrlkey /itemnotify "%s" leftmouseup', mat)
            end
            if pack == 'Enviro' then
                if mq.TLO.Cursor() then mq.cmdf('/itemnotify enviro%s leftmouseup', i) end
            else
                if mq.TLO.Cursor() then mq.cmdf('/itemnotify in %s %s leftmouseup', pack, i) end
            end
            waitForEmptyCursor()
        end

        -- Perform the combine
        mq.cmdf('/combine %s', pack)
        waitForCursor()
        clearCursor()
        crafting.NumMade = crafting.NumMade + 1
    end
end

local function craftInTradeskillWindow(pack)
    if not selectedRecipe then return end
    local recipeName = selectedRecipe.OutputName and selectedRecipe.OutputName or selectedRecipe.Recipe
    local recipeExists = mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').List(recipeName)()
    if not recipeExists then
        mq.cmd('/nomodkey /notify TradeskillWnd COMBW_SearchTextEdit leftmouseup')
        mq.delay(50)
        mq.TLO.Window('TradeskillWnd/COMBW_SearchTextEdit').SetText(recipeName)()
        mq.delay(50)
        mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').Select(recipeName)()
        mq.delay(200)
        recipeExists = mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').List(recipeName)()
        if not recipeExists then
            mq.delay(30000, function() return mq.TLO.Window('TradeskillWnd/COMBW_SearchButton').Enabled() end)
            mq.cmd('/nomodkey /notify TradeskillWnd COMBW_SearchButton leftmouseup')
            mq.delay(1000)
            mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').Select(recipeName)()
            mq.delay(500)
            recipeExists = mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').List(recipeName)()
            if not recipeExists then
                craftInExperimental(pack)
                return
            end
        end
    end
    if selectedTradeskill == 'Jewelry Making' and mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').List(recipeExists+1)() == recipeName then
        -- JC special case for enchanted bars
        mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').Select(recipeExists+1)()
    end
    crafting.NumMade = 0
    while crafting.NumMade < buying.Qty do
        if not crafting.Status then return end
        if crafting.StopAtTrivial and (mq.TLO.Me.Skill(selectedTradeskill or '')() >= selectedRecipe.Trivial or mq.TLO.Me.Skill(selectedTradeskill or '')() == 300) then
            crafting.SuccessMessage = 'Reached trivial for recipe!'
            return
        end
        if mq.TLO.Me.FreeInventory() == 0 then
            crafting.FailedMessage = 'Inventory is full!'
            return
        end
        if not crafting.Fast then
            clearCursor()
            mq.delay(1000, function() return mq.TLO.Window('TradeskillWnd/CombineButton').Enabled() end)
        end
        if mq.TLO.Window('TradeskillWnd/CombineButton').Enabled() then
            mq.cmdf('/nomodkey /notify TradeskillWnd CombineButton leftmouseup')
            if not crafting.Fast then
                waitForCursor()
                clearCursor()
                mq.doevents()
                if crafting.OutOfMats and not mq.TLO.Cursor() then
                    if crafting.NumMade == 0 and mq.TLO.Window('TradeskillWnd/COMBW_RecipeList').List(recipeExists+1)() then
                        crafting.FailedMessage = 'Multiple recipe options, select the correct one and try again.'
                    end
                    break
                else
                    clearCursor()
                    crafting.OutOfMats = false
                end
            else
                mq.cmd('/autoinv')
                mq.cmd('/autoinv')
            end
            crafting.NumMade = crafting.NumMade + 1
        else
            clearCursor()
        end
    end
end

local function craftInInvSlot()
    if not selectedRecipe then return end
    if mq.TLO.Window('TradeskillWnd').Open() then
        craftInTradeskillWindow()
        return
    end
    local container_pack = -1
    local container_item = mq.TLO.FindItem('='..selectedRecipe.Container)
    if container_item.ItemSlot2() ~= -1 then
        -- move container to top level inventory slot
        mq.cmdf('/nomodkey /ctrlkey /itemnotify "%s" leftmouseup', selectedRecipe.Container)
        waitForCursor()
        clearCursor()

        container_item = mq.TLO.FindItem('='..selectedRecipe)
        -- container still not in top level slot
        if container_item.ItemSlot2() ~= -1 then
            printf('No top level inventory slot available for container')
            return
        end
        container_pack = container_item.ItemSlot() - 22
    else
        container_pack = container_item.ItemSlot() - 22

        -- container must be empty
        if container_item.Items() > 0 then
            mq.cmdf('/keypress OPEN_INV_BAGS')
            for i=0,container_item.Container() do
                if container_item.Item(i)() then
                    local new_location = findOpenSlot(container_pack+22)
                    mq.cmdf('/nomodkey /shiftkey /itemnotify in pack%s %s leftmouseup', container_pack, i)
                    waitForCursor()
                    mq.cmdf('/itemnotify %s leftmouseup', new_location)
                    waitForEmptyCursor()
                end
            end
            mq.cmdf('/keypress CLOSE_INV_BAGS')
        end
    end
    if mq.TLO.Window('pack'..container_pack)() then mq.cmdf('/keypress CLOSE_INV_BAGS') mq.delay(1) mq.delay(100) end
    mq.cmdf('/itemnotify "pack%s" rightmouseup', container_pack)
    mq.delay(10)
    craftInTradeskillWindow('pack'..container_pack)
    clearCursor()
end

local function craftAtStation()
    if not selectedRecipe then return end
    printf('Moving to crafting station')
    mq.cmdf('/nav loc '..recipes.Stations[mq.TLO.Zone.ShortName()][selectedRecipe.Container]..' log=off')
    mq.delay(250)
    mq.delay(30000, function() return not mq.TLO.Navigation.Active() end)
    printf('Opening crafting station')
    mq.cmd('/itemtar')
    mq.delay(5)
    mq.cmd('/click left item')
    mq.delay(500, function() return mq.TLO.Window('TradeskillWnd').Open() end)
    mq.doevents('inuse')
    if not crafting.Status then return end
    if not mq.TLO.Window('TradeskillWnd').Open() then return end
    craftInTradeskillWindow('Enviro')
    clearCursor()
end

local function craft()
    if not selectedRecipe or not shouldCraft() then crafting.Status = false return end
    if recipes.Stations[mq.TLO.Zone.ShortName()] and recipes.Stations[mq.TLO.Zone.ShortName()][selectedRecipe.Container] then
        if mq.TLO.Window('Enviro').Open() then
            craftInExperimental('Enviro')
        else
            craftAtStation()
        end
    elseif invSlotContainers[selectedRecipe.Container] then
        craftInInvSlot()
    else
        -- special cases, feir`dal for mithril, etc.
    end
    clearCursor()
end

for name,ingredient in pairs(recipes.Materials) do
    table.insert(ingredientsArray, {Name=name, Location=ingredient.Location, SourceType=ingredient.SourceType, Tool=ingredient.Tool, Zone=ingredient.Zone})
end
table.sort(ingredientsArray, function(a,b) return a.Name < b.Name end)

mq.imgui.init('radix', radixGUI)

mq.event('missingmaterial', '#*#You are missing a#*#', function() crafting.OutOfMats = true end)
mq.event('inuse', '#*#Someone else is using that#*#', function()
    crafting.Status = false
    crafting.FailedMessage = 'Crafting station already in use!'
    printf('Crafting station already in use!')
end)

while true do
    if selectedRecipe then
        if buying.Status then
            buy()
        elseif selling.Status then
            sell()
        elseif requesting.Status then
            request()
        elseif crafting.Status then
            craft()
            for i=#thingsToCraft, 1, -1 do
                selectedRecipe = thingsToCraft[i]
                if i == 1 then crafting.StopAtTrivial = tempStopAtTriv end
                craft()
            end
            crafting.Status = false
            thingsToCraft = {}
        end
    end
    mq.delay(1000)
end