--- STEAMODDED HEADER
--- MOD_NAME: Hold to Confirm
--- MOD_ID: hold-to-confirm
--- MOD_AUTHOR: [vapecoder]
--- MOD_DESCRIPTION: Hold buttons to confirm purchases instead of instant click
--- VERSION: 1.0.0
--- PREFIX: htc

-- Track active holds
local active_holds = {}

-- Store original validation functions
local original_can_buy = G.FUNCS.can_buy
local original_can_sell_card = G.FUNCS.can_sell_card
local original_can_open = G.FUNCS.can_open
local original_can_redeem = G.FUNCS.can_redeem

-- Store original action functions  
local original_buy_from_shop = G.FUNCS.buy_from_shop
local original_sell_card = G.FUNCS.sell_card
local original_use_card = G.FUNCS.use_card
local original_buy_and_use = G.FUNCS.buy_and_use

-- Reset card state without breaking controller navigation
local function reset_card_interaction_state(card)
    if not card then return end
    
    -- Clear any processing flags
    card.being_sold = nil
    card.being_bought = nil
    card.being_used = nil
    
    -- Clear forced selection flag (native Balatro pattern)
    if card.ability then
        card.ability.forced_selection = nil
    end
    
    -- Don't interfere with controller focus - just let the game handle it naturally
end

-- Re-enable button after cancelled hold
local function re_enable_button(e)
    if not e or not e.config then return end
    
    -- Reset the disabled state
    e.disable_button = false
    e.config.disable_button = false
    
    -- Also ensure the button state is properly restored
    if e.config.button then
        -- Button is still valid, just needed re-enabling
    end
end

-- Get button identifier for tracking
local function get_button_key(e)
    return tostring(e.config.ref_table) .. "_" .. (e.config.ref_table.area and tostring(e.config.ref_table.area) or "")
end

-- Card animations during hold (vertical bounce or shake)
local function apply_random_card_effect(card, progress)
    if not card or not card.juice_up then return end
    
    local card_seed = tostring(card):sub(-2)
    local effect_type = (tonumber(card_seed, 16) or 0) % 2 + 1
    
    local intensity = 0.05 + (progress * 0.15)
    
    if effect_type == 1 then
        card:juice_up(intensity, 0.1) -- Shake
    else
        card:juice_up(0, intensity * 2) -- Vertical bounce
    end
end

-- Color interpolation
local function mix_colours(color1, color2, ratio)
    ratio = math.max(0, math.min(1, ratio))
    return {
        color1[1] + (color2[1] - color1[1]) * ratio,
        color1[2] + (color2[2] - color1[2]) * ratio,
        color1[3] + (color2[3] - color1[3]) * ratio,
        color1[4] and color2[4] and (color1[4] + (color2[4] - color1[4]) * ratio) or 1
    }
end

-- Progress color transition from black to target color
local function get_progress_fill_color(base_color, progress)
    local black = {0, 0, 0, 1}
    return mix_colours(black, base_color, progress)
end

-- Main hold-to-confirm function
local function start_hold_to_confirm(e, original_action, action_name)
    local card = e.config.ref_table
    local button_key = get_button_key(e)
    local hold_id = tostring(card) .. "_" .. tostring(G.TIMERS.REAL) .. "_" .. action_name
    local start_time = G.TIMERS.REAL
    local duration = 0.45
    
    play_sound('tarot1')
    
    active_holds[hold_id] = {
        start_time = start_time,
        card = card,
        action = original_action,
        button_key = button_key,
        event_object = e,
        completed = false,
        cancelled = false
    }
    
    G.E_MANAGER:add_event(Event({
        trigger = 'condition',
        func = function()
            local hold_data = active_holds[hold_id]
            if not hold_data or hold_data.completed then
                return true
            end
            
            -- Check if button is still being held
            local button_held = false
            
            -- Check mouse
            if love.mouse.isDown(1) then
                button_held = true
            end
            
            -- Check gamepad buttons
            if G.CONTROLLER and G.CONTROLLER.held_buttons then
                if G.CONTROLLER.held_buttons["rightshoulder"] or 
                   G.CONTROLLER.held_buttons["leftshoulder"] or 
                   G.CONTROLLER.held_buttons["a"] then
                    button_held = true
                end
            end
            
            -- Cancel if no button is held
            if not button_held then
                hold_data.completed = true
                hold_data.cancelled = true
                active_holds[hold_id] = nil
                
                play_sound('tarot2')
                
                if hold_data.card then
                    hold_data.card.T.sx = 1
                    hold_data.card.T.sy = 1
                    hold_data.card.T.r = 0
                end
                
                reset_card_interaction_state(hold_data.card)
                
                re_enable_button(hold_data.event_object)
                
                return true
            end
            
            local elapsed = G.TIMERS.REAL - hold_data.start_time
            local progress = elapsed / duration
            
            apply_random_card_effect(hold_data.card, progress)
            
            -- Complete after duration
            if elapsed >= duration then
                hold_data.completed = true
                active_holds[hold_id] = nil
                
                if hold_data.card then
                    hold_data.card.T.sx = 1
                    hold_data.card.T.sy = 1
                    hold_data.card.T.r = 0
                end
                
                play_sound('button')
                
                hold_data.action()
                return true
            end
            
            return false
        end,
        blocking = false,
        blockable = false
    }))
end

-- Hook validation functions with progress colors
G.FUNCS.can_buy = function(e)
    local button_key = get_button_key(e)
    
    local is_holding = false
    local progress = 0
    for _, hold_data in pairs(active_holds) do
        if hold_data.button_key == button_key and not hold_data.completed then
            is_holding = true
            local elapsed = G.TIMERS.REAL - hold_data.start_time
            progress = math.min(1, elapsed / 0.45)
            break
        end
    end
    
    if (e.config.ref_table.cost <= G.GAME.dollars - G.GAME.bankrupt_at) or (e.config.ref_table.cost <= 0) then
        if is_holding then
            e.config.colour = get_progress_fill_color(G.C.ORANGE, progress)
        else
            e.config.colour = G.C.ORANGE
        end
        e.config.button = 'htc_confirm_buy'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.can_sell_card = function(e)
    local button_key = get_button_key(e)
    
    local is_holding = false
    local progress = 0
    for _, hold_data in pairs(active_holds) do
        if hold_data.button_key == button_key and not hold_data.completed then
            is_holding = true
            local elapsed = G.TIMERS.REAL - hold_data.start_time
            progress = math.min(1, elapsed / 0.45)
            break
        end
    end
    
    if e.config.ref_table:can_sell_card() then 
        if is_holding then
            e.config.colour = get_progress_fill_color(G.C.GREEN, progress)
        else
            e.config.colour = G.C.GREEN
        end
        e.config.button = 'htc_confirm_sell'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.can_open = function(e)
    local button_key = get_button_key(e)
    
    local is_holding = false
    local progress = 0
    for _, hold_data in pairs(active_holds) do
        if hold_data.button_key == button_key and not hold_data.completed then
            is_holding = true
            local elapsed = G.TIMERS.REAL - hold_data.start_time
            progress = math.min(1, elapsed / 0.45)
            break
        end
    end
    
    if not ((e.config.ref_table.cost) > 0 and (e.config.ref_table.cost > G.GAME.dollars - G.GAME.bankrupt_at)) then
        if is_holding then
            e.config.colour = get_progress_fill_color(G.C.GREEN, progress)
        else
            e.config.colour = G.C.GREEN
        end
        e.config.button = 'htc_confirm_open'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.can_redeem = function(e)
    local button_key = get_button_key(e)
    
    local is_holding = false
    local progress = 0
    for _, hold_data in pairs(active_holds) do
        if hold_data.button_key == button_key and not hold_data.completed then
            is_holding = true
            local elapsed = G.TIMERS.REAL - hold_data.start_time
            progress = math.min(1, elapsed / 0.45)
            break
        end
    end
    
    if not (e.config.ref_table.cost > G.GAME.dollars - G.GAME.bankrupt_at) then
        if is_holding then
            e.config.colour = get_progress_fill_color(G.C.GREEN, progress)
        else
            e.config.colour = G.C.GREEN
        end
        e.config.button = 'htc_confirm_redeem'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

-- Hold-to-confirm action functions
G.FUNCS.htc_confirm_buy = function(e)
    start_hold_to_confirm(e, function()
        original_buy_from_shop(e)
    end, "buy")
end

G.FUNCS.htc_confirm_sell = function(e)
    start_hold_to_confirm(e, function()
        original_sell_card(e)
    end, "sell")
end

G.FUNCS.htc_confirm_open = function(e)
    start_hold_to_confirm(e, function()
        original_use_card(e)
    end, "open")
end

G.FUNCS.htc_confirm_redeem = function(e)
    start_hold_to_confirm(e, function()
        original_use_card(e)
    end, "redeem")
end

G.FUNCS.buy_and_use = function(e)
    start_hold_to_confirm(e, function()
        original_buy_and_use(e)
    end, "buy_and_use")
end

print("Hold to Confirm mod loaded - v1.0.0 (SIMPLE BLACK-TO-COLOR)")
print("✓ WORKING foundation from 081005 backup")
print("✓ Duration: 0.45 seconds (fast)")
print("✓ Sound effects: tarot1 → button (completion) / tarot2 (early release)")
print("✓ SIMPLE PROGRESS: Black-to-color transition")
print("✓ SIMPLE ANIMATIONS: Only vertical bounce and traditional shake")
print("✓ Perfect retriggering with button re-enabling")