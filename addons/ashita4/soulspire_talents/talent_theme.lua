-- SoulspireXI Weapon Skill Talent Theme & Classic RPG Drawing Primitives
--
-- Palette verified directly from SoulspireXI website (site/styles.css):
--   --bg-deep:      #070B14    --accent-gold:    #FBBF24 (warm metallic #E8BD70)
--   --bg-surface:   #0F1629    --accent-cyan:    #38BDF8 (aether #39CFE5)
--   --bg-card:      #131C33    --accent-purple:  #A855F7 (crystal #8063BC)
--   --bg-elevated:  #1C2847    --accent-emerald: #10B981
--   --text-primary: #F1F5F9    --accent-rose:    #F43F5E
--   --text-muted:   #94A3B8
--
-- Branch visual identity:
--   Damage  -> Soul Gold    (left column)
--   Soul    -> Crystal Violet (CENTERPIECE column)
--   Utility -> Aether Cyan  (right column)
local bit = require('bit')

local T = {}

local function rgba(hex, a)
    local r = tonumber(hex:sub(2, 3), 16) / 255.0
    local g = tonumber(hex:sub(4, 5), 16) / 255.0
    local b = tonumber(hex:sub(6, 7), 16) / 255.0
    return { r, g, b, a or 1.0 }
end

T.COLORS =
{
    -- Official site/styles.css dark surfaces
    abyss        = rgba('#070B14', 0.98),
    surface      = rgba('#0F1629', 0.97),
    card         = rgba('#131C33', 0.96),
    cardHover    = rgba('#192542', 0.98),
    elevated     = rgba('#1C2847', 0.98),
    stoneDark    = rgba('#0B1019', 0.98),
    stonePanel   = rgba('#151928', 0.97),

    -- Borders & engraved metalwork
    borderSubtle = { 0.58, 0.64, 0.72, 0.22 },
    borderMetal  = rgba('#3B4664', 0.85),
    borderGold   = rgba('#E8BD70', 0.65),
    borderGoldHi = rgba('#FBBF24', 0.95),
    borderCyan   = rgba('#38BDF8', 0.72),
    borderViolet = rgba('#A855F7', 0.82),

    -- Typography
    textPrimary  = rgba('#F1F5F9', 1.00),
    textSecond   = rgba('#CBD5E1', 1.00),
    textMuted    = rgba('#94A3B8', 1.00),
    textDim      = rgba('#64748B', 1.00),

    -- Official accents
    gold         = rgba('#FBBF24', 1.00),
    goldWarm     = rgba('#E8BD70', 1.00),
    goldDeep     = rgba('#78521A', 0.95),
    goldGlow     = rgba('#FBBF24', 0.22),

    cyan         = rgba('#38BDF8', 1.00),
    cyanAether   = rgba('#39CFE5', 1.00),
    cyanDeep     = rgba('#134E6F', 0.95),
    cyanGlow     = rgba('#38BDF8', 0.20),

    violet       = rgba('#A855F7', 1.00),
    violetCryst  = rgba('#8063BC', 1.00),
    violetDeep   = rgba('#2C1A4D', 0.95),
    violetBg     = rgba('#181330', 0.96),
    violetGlow   = rgba('#A855F7', 0.24),

    emerald      = rgba('#10B981', 1.00),
    emeraldDeep  = rgba('#064E3B', 0.92),
    rose         = rgba('#F43F5E', 1.00),
    roseDeep     = rgba('#581426', 0.92),

    -- Node states
    nodeLockedBg = rgba('#0B101D', 0.95),
    nodeAvailBg  = rgba('#141E36', 0.97),
    nodeLearnBg  = rgba('#1E2438', 0.98),
    nodeMaxBg    = rgba('#262019', 0.98),
    lineLocked   = rgba('#334155', 0.65),
}

T.BRANCHES =
{
    damage = {
        key       = 'damage',
        title     = 'DAMAGE',
        subtitle  = 'Offensive Execution',
        accent    = T.COLORS.gold,
        accentAlt = T.COLORS.goldWarm,
        deep      = T.COLORS.goldDeep,
        glow      = T.COLORS.goldGlow,
        panelBg   = rgba('#141522', 0.92),
    },
    soul = {
        key       = 'soul',
        title     = 'SOUL',
        subtitle  = 'Specialization Core',
        accent    = T.COLORS.violet,
        accentAlt = T.COLORS.violetCryst,
        deep      = T.COLORS.violetDeep,
        glow      = T.COLORS.violetGlow,
        panelBg   = T.COLORS.violetBg,
        centerpiece = true,
    },
    utility = {
        key       = 'utility',
        title     = 'UTILITY',
        subtitle  = 'Tactical Control',
        accent    = T.COLORS.cyan,
        accentAlt = T.COLORS.cyanAether,
        deep      = T.COLORS.cyanDeep,
        glow      = T.COLORS.cyanGlow,
        panelBg   = rgba('#0E182B', 0.92),
    },
}

T.ROLE_COLORS =
{
    Damage  = T.COLORS.gold,
    Tank    = T.COLORS.cyan,
    Healer  = T.COLORS.emerald,
    Support = T.COLORS.violet,
}

function T.u32(col, imgui)
    if imgui and imgui.ColorConvertFloat4ToU32 then
        return imgui.ColorConvertFloat4ToU32(col)
    end
    local r = math.floor(math.max(0, math.min(1, col[1] or 0)) * 255 + 0.5)
    local g = math.floor(math.max(0, math.min(1, col[2] or 0)) * 255 + 0.5)
    local b = math.floor(math.max(0, math.min(1, col[3] or 0)) * 255 + 0.5)
    local a = math.floor(math.max(0, math.min(1, col[4] or 1)) * 255 + 0.5)
    local val = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
    if val < 0 then val = val + 4294967296 end
    return val
end

-- Classic dark-fantasy engraved panel with subtle corner filigree ticks
function T.drawEngravedPanel(dl, imgui, x, y, w, h, fillCol, borderCol, accentCol, rounding)
    local r = rounding or 6
    dl:AddRectFilled({ x, y }, { x + w, y + h }, T.u32(fillCol, imgui), r)
    dl:AddRect({ x, y }, { x + w, y + h }, T.u32(borderCol, imgui), r, 0, 1.2)
    -- Inner subtle bevel
    dl:AddRect({ x + 2, y + 2 }, { x + w - 2, y + h - 2 }, T.u32({ 0.02, 0.03, 0.06, 0.65 }, imgui), math.max(1, r - 2), 0, 1.0)
    if accentCol then
        local c = T.u32(accentCol, imgui)
        local len = 10
        -- Top-left & top-right metallic corner accents
        dl:AddLine({ x + 3, y + 3 }, { x + 3 + len, y + 3 }, c, 1.6)
        dl:AddLine({ x + 3, y + 3 }, { x + 3, y + 3 + len }, c, 1.6)
        dl:AddLine({ x + w - 3 - len, y + 3 }, { x + w - 3, y + 3 }, c, 1.6)
        dl:AddLine({ x + w - 3, y + 3 }, { x + w - 3, y + 3 + len }, c, 1.6)
        -- Bottom-left & bottom-right metallic corner accents
        dl:AddLine({ x + 3, y + h - 3 }, { x + 3 + len, y + h - 3 }, c, 1.6)
        dl:AddLine({ x + 3, y + h - 3 - len }, { x + 3, y + h - 3 }, c, 1.6)
        dl:AddLine({ x + w - 3 - len, y + h - 3 }, { x + w - 3, y + h - 3 }, c, 1.6)
        dl:AddLine({ x + w - 3, y + h - 3 - len }, { x + w - 3, y + h - 3 }, c, 1.6)
    end
end

-- Procedural RPG vector emblem inside a 56x56 talent icon tile (zero ugly empty squares)
function T.drawNodeGlyph(dl, imgui, cx, cy, radius, branchKey, tier, stateCol, isLocked)
    local col = T.u32(isLocked and T.COLORS.textDim or stateCol, imgui)
    local dim = T.u32({ stateCol[1], stateCol[2], stateCol[3], isLocked and 0.14 or 0.30 }, imgui)
    local r = radius

    if branchKey == 'soul' then
        -- Soul Centerpiece: Faceted Crystal Diamond + inner core + aura ring
        dl:AddCircleFilled({ cx, cy }, r * 0.85, dim, 20)
        dl:AddQuadFilled(
            { cx, cy - r * 0.88 },
            { cx + r * 0.62, cy },
            { cx, cy + r * 0.88 },
            { cx - r * 0.62, cy },
            dim
        )
        dl:AddQuad(
            { cx, cy - r * 0.88 },
            { cx + r * 0.62, cy },
            { cx, cy + r * 0.88 },
            { cx - r * 0.62, cy },
            col, 1.9
        )
        dl:AddLine({ cx, cy - r * 0.88 }, { cx, cy + r * 0.88 }, col, 1.1)
        dl:AddCircleFilled({ cx, cy }, r * (0.22 + (tier or 1) * 0.04), col, 12)
    elseif branchKey == 'damage' then
        -- Damage: Crossed blade / spearhead emblem
        dl:AddCircleFilled({ cx, cy }, r * 0.72, dim, 16)
        dl:AddLine({ cx - r * 0.65, cy + r * 0.65 }, { cx + r * 0.65, cy - r * 0.65 }, col, 2.4)
        dl:AddLine({ cx + r * 0.18, cy - r * 0.68 }, { cx + r * 0.68, cy - r * 0.68 }, col, 2.0)
        dl:AddLine({ cx + r * 0.68, cy - r * 0.68 }, { cx + r * 0.68, cy - r * 0.18 }, col, 2.0)
        -- Guard crossbar
        dl:AddLine({ cx - r * 0.48, cy + r * 0.18 }, { cx - r * 0.18, cy + r * 0.48 }, col, 2.0)
        if (tier or 1) >= 3 then
            dl:AddLine({ cx - r * 0.60, cy - r * 0.60 }, { cx + r * 0.60, cy + r * 0.60 }, col, 1.6)
        end
    elseif branchKey == 'utility' then
        -- Utility: Aether compass / tactical ring with cardinal ticks
        dl:AddCircleFilled({ cx, cy }, r * 0.70, dim, 18)
        dl:AddCircle({ cx, cy }, r * 0.68, col, 20, 1.8)
        dl:AddLine({ cx, cy - r * 0.88 }, { cx, cy - r * 0.35 }, col, 1.8)
        dl:AddLine({ cx, cy + r * 0.35 }, { cx, cy + r * 0.88 }, col, 1.8)
        dl:AddLine({ cx - r * 0.88, cy }, { cx - r * 0.35, cy }, col, 1.8)
        dl:AddLine({ cx + r * 0.35, cy }, { cx + r * 0.88, cy }, col, 1.8)
        dl:AddCircleFilled({ cx, cy }, r * 0.20, col, 12)
    else
        -- Evolution / Skillchain: Starburst crest
        dl:AddCircle({ cx, cy }, r * 0.72, col, 18, 1.8)
        dl:AddCircleFilled({ cx, cy }, r * 0.28, col, 14)
    end
end

-- Crisp 14x14 weapon family glyph for the left Weapon Skill Selector
function T.drawWeaponGlyph(dl, imgui, cx, cy, skillId, col)
    local c = T.u32(col, imgui)
    if skillId == 25 or skillId == 26 or skillId == 27 then
        -- Ranged / Throwing: target ring + arrow
        dl:AddCircle({ cx, cy }, 5.5, c, 12, 1.3)
        dl:AddLine({ cx - 6, cy + 5 }, { cx + 6, cy - 5 }, c, 1.5)
    elseif skillId == 11 or skillId == 12 then
        -- Staff / Club: vertical scepter + orb
        dl:AddLine({ cx, cy - 4 }, { cx, cy + 7 }, c, 1.6)
        dl:AddCircleFilled({ cx, cy - 4 }, 3.2, c, 10)
    elseif skillId == 1 then
        -- H2H: armored gauntlet diamond
        dl:AddQuad({ cx, cy - 6 }, { cx + 6, cy }, { cx, cy + 6 }, { cx - 6, cy }, c, 1.6)
    else
        -- Bladed / Polearm / Axe / Scythe: diagonal blade
        dl:AddLine({ cx - 5, cy + 5 }, { cx + 5, cy - 5 }, c, 1.8)
        dl:AddLine({ cx - 3, cy + 1 }, { cx - 1, cy + 3 }, c, 1.6)
    end
end

return T
