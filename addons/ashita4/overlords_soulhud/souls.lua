local function element(id, label, kind, field, max, unit)
    return { id = id, label = label, type = kind, field = field or id, max = max, unit = unit }
end

return {
    flintlock = {
        title = 'COR · Flintlock',
        elements = {
            element('powder', 'Black Powder', 'stack', 'powder', 3, 'rounds'),
            element('mark_rem', 'Powder Mark', 'timer', 'mark_rem', nil, 's'),
        },
    },
    gambler = {
        title = 'COR · Gambler',
        elements = {
            element('rolls', 'Active Phantom Rolls', 'stack', 'rolls', 3),
            element('ante_n', 'Ante / Wagers', 'counter', 'ante_n'),
            element('ante_hp', 'Ante HP', 'counter', 'ante_hp', nil, 'HP'),
            element('ante_tp', 'Ante TP', 'counter', 'ante_tp', nil, 'TP'),
            element('roll_tot', 'Current Roll', 'counter', 'roll_tot'),
            element('overdrive', 'Lucky Overdrive', 'toggle', 'overdrive'),
            element('du_rem', 'Double Up Window', 'timer', 'du_rem', nil, 's'),
            element('roll_lock', 'Roll Lock', 'cooldown', 'roll_lock', nil, 's'),
            element('last_cdr', 'Jackpot Cooldown Reduction', 'counter', 'last_cdr', nil, 's'),
            element('debt_rem', 'House Debt', 'timer', 'debt_rem', nil, 's'),
            element('snake_act', 'Snake Eye', 'toggle', 'snake_act'),
            element('cc_type', 'Deck Effect', 'counter', 'cc_type'),
            element('cc_rem', 'Deck Effect Duration', 'timer', 'cc_rem', nil, 's'),
        },
    },
    miragesentinel = {
        title = 'DNC · Mirage Sentinel',
        elements = {
            element('fm', 'Finishing Moves', 'stack', 'fm', 5),
            element('fan_act', 'Fan Dance', 'toggle', 'fan_act'),
            element('fan_dt', 'Fan Dance Mitigation', 'gauge', 'fan_dt', 45, '%'),
            element('fan_rem', 'Fan Dance Duration', 'timer', 'fan_rem', nil, 's'),
            element('issek_rem', 'Parry Window', 'timer', 'issek_rem', nil, 's'),
            element('parry_fm', 'Parry-Generated Moves', 'counter', 'parry_fm'),
            element('aegis_hp', 'Flourish Shield', 'gauge', 'aegis_hp', nil, 'HP'),
            element('aegis_rem', 'Shield Duration', 'timer', 'aegis_rem', nil, 's'),
        },
    },
}
