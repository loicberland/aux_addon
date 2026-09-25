module 'aux.core.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local stack = require 'aux.core.stack'

local state

local function continue_after_post(k)
    -- TBC 2.4.3 / CMaNGOS:
    -- the auction success message can arrive before the auction sell slot
    -- is fully cleared client-side. Starting the next stack immediately can
    -- therefore make StartAuction use a stale/non-existent item.
    local delay_done = later(.75)
    local timeout = later(5)

    return when(function()
        if timeout() then
            return true
        end

        local sell_item_name = GetAuctionSellItemInfo()
        return delay_done() and not sell_item_name
    end, function()
        -- If the sell slot is still occupied after the timeout, stop cleanly.
        if GetAuctionSellItemInfo() then
            return stop()
        end

        return k()
    end)
end

function process()
    if state.posted < state.count then

        local stacking_complete

        local send_signal, signal_received = signal()
        when(signal_received, function()
            local slot = signal_received()[1]
            if slot then
                return post_auction(slot, process)
            else
                return stop()
            end
        end)

        return stack.start(state.item_key, state.stack_size, send_signal)
    end

    return stop()
end

function post_auction(slot, k)
    local item_info = info.container_item(unpack(slot))
    if item_info and item_info.item_key == state.item_key and info.auctionable(item_info.tooltip, nil, true) and item_info.aux_quantity == state.stack_size then

        ClearCursor()
        ClickAuctionSellItemButton()
        ClearCursor()
        PickupContainerItem(unpack(slot))
        ClickAuctionSellItemButton()
        ClearCursor()

        local send_signal, signal_received = signal()
        local timeout = later(5)

        -- Register BEFORE StartAuction so the confirmation cannot be missed.
        local listener_id = event_listener('CHAT_MSG_SYSTEM', function(kill)
            if arg1 == ERR_AUCTION_STARTED then
                send_signal()
                kill()
            end
        end)

        StartAuction(
            max(1, round(state.unit_start_price * item_info.aux_quantity)),
            round(state.unit_buyout_price * item_info.aux_quantity),
            state.duration
        )

        return when(function()
            return signal_received() or timeout()
        end, function()
            kill_listener(listener_id)

            if not signal_received() then
                return stop()
            end

            state.posted = state.posted + 1

            -- Do NOT immediately start the next stack.
            -- Wait until the AH sell slot is really free first.
            return continue_after_post(k)
        end)
    else
        return stop()
    end
end

function M.stop()
    if state then
        kill_thread(state.thread_id)

        local callback = state.callback
        local posted = state.posted

        state = nil

        if callback then
            callback(posted)
        end
    end
end

function M.start(item_key, stack_size, duration, unit_start_price, unit_buyout_price, count, callback)
    stop()
    state = {
        thread_id = thread(process),
        item_key = item_key,
        stack_size = stack_size,
        duration = duration,
        unit_start_price = unit_start_price,
        unit_buyout_price = unit_buyout_price,
        count = count,
        posted = 0,
        callback = callback,
    }
end
