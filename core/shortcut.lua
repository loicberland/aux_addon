module 'aux.core.shortcut'

local T = require 'T'
local aux = require 'aux'
local info = require 'aux.util.info'

do
    local orig = SetItemRef
    _G.SetItemRef = T.vararg-function(arg)
        if arg[3] ~= 'RightButton' or not aux.index(aux.get_tab(), 'CLICK_LINK') or not strfind(arg[1], '^item:%d+') then
            return orig(unpack(arg))
        end
        local item_info = info.item(tonumber(aux.select(3, strfind(arg[1], '^item:(%d+)'))))
        if item_info then
            return aux.get_tab().CLICK_LINK(item_info)
        end
    end
end

do
    local orig = UseContainerItem
    _G.UseContainerItem = T.vararg-function(arg)
        if aux.modified() or not aux.get_tab() then
            return orig(unpack(arg))
        end
        local item_info = info.container_item(arg[1], arg[2])
        if item_info and aux.get_tab().USE_ITEM then
            aux.get_tab().USE_ITEM(item_info)
        end
    end
end

-- BagShui handles item button clicks itself before they necessarily reach
-- UseContainerItem. Hook its inventory click handler directly so right-clicking
-- an item keeps the same Aux shortcut behaviour as the Blizzard bags.
do
    local hooked

    local function hook_bagshui()
        if hooked then return end

        local bagshui = _G.Bagshui
        local inventory = bagshui and bagshui.prototypes and bagshui.prototypes.Inventory
        if not inventory or type(inventory.ItemButton_OnClick) ~= 'function' then return end

        local orig = inventory.ItemButton_OnClick
        inventory.ItemButton_OnClick = function(self, mouse_button, is_drag)
            local tab = aux.get_tab()
            local button = _G.this
            local data = button and button.bagshuiData

            if mouse_button == 'RightButton' and not is_drag and not aux.modified()
                and tab and tab.USE_ITEM and data and data.bagNum and data.slotNum then
                local item_info = info.container_item(data.bagNum, data.slotNum)
                if item_info then
                    tab.USE_ITEM(item_info)
                    return
                end
            end

            return orig(self, mouse_button, is_drag)
        end
        hooked = true
    end

    function aux.handle.LOAD2()
        hook_bagshui()
    end
end
