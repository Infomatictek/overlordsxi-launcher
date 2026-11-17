Overlords = { }

local MESSAGE_SYSTEM_3 = 29

-- Custom OverlordsXI Job Abilities keyed by client ID (server abilityId + Ashita.AbilityOffset.ABILITY [512]).
Overlords.CustomAbilities =
{
    -- SCH (Eos / Titania Companions)
    [743] = 'Call Eos',              -- 231
    [801] = 'Call Titania',          -- 289

    -- WAR Specs
    [908] = 'Tactical Breach',       -- 396
    [909] = 'Formation: Bulwark',    -- 397
    [910] = 'Battle Cadence',        -- 398
    [911] = 'Rallying Horn',         -- 399
    [912] = 'Bloodlust Surge',       -- 400
    [913] = 'Savage Cleave',         -- 401
    [914] = 'Crimson Crush',         -- 402
    [915] = 'Vanguard Ward',         -- 403

    -- DNC Chakram Spec
    [916] = 'Throwing Stance',       -- 404

    -- BLM Necromancer Spec
    [917] = 'Summon Undead Warrior', -- 405
    [918] = 'Summon Undead Mage',    -- 406
    [919] = 'Corpse Explosion',      -- 407
    [920] = 'Grim Reaping',          -- 408
    [921] = 'Grim Incantations',     -- 409
    [922] = 'Summon Corse',          -- 410
    [923] = 'Summon Dullahan',       -- 411
    [931] = 'Grave Provoke',         -- 419
    [932] = 'Black Cloud',           -- 420
    [933] = 'Bone Aegis',            -- 421
    [934] = 'Blood Saber',           -- 422
    [935] = 'Aegis Schism',          -- 423
    [936] = 'Necrotic Bolt',         -- 424
    [937] = 'Covenant of Ash',       -- 425
    [938] = 'Curse of the Fallen',   -- 426
    [939] = 'Soul Harvest',          -- 427
    [940] = 'Danse Macabre',         -- 428

    -- RUN Specs
    [924] = 'Iron Battuta',          -- 412
    [925] = 'Runic Aegis',           -- 413
    [926] = 'Runic Convergence',     -- 414
    [927] = 'Effusion Slash',        -- 415
    [928] = 'Overcharge Runes',      -- 416
    [929] = 'Font of Life',          -- 417
    [930] = 'Sanctified Ward',       -- 418

    -- MNK Chi Weaver Spec
    [941] = 'Resonant Chi',          -- 429
    [942] = 'Tranquil Lotus',        -- 430
    [943] = 'Inner Harmony',         -- 431

    -- SAM Imperial Archer Spec
    [950] = 'Oisoya Shot',           -- 438

    -- PLD Aegis Templar Spec
    [951] = 'Aegis Consecration',    -- 439
    [952] = 'Judgment Gavel',        -- 440

    -- BST Alpha Warden Spec
    [953] = 'Soul Bond',             -- 441
    [954] = 'Feral Roar',            -- 442

    -- NIN Kagemusha Spec
    [955] = 'Kage Bunshin',          -- 443
    [956] = 'Smoke Lotus',           -- 444

    -- BLU Azure Bastion Spec
    [957] = 'Behemoth Roar',         -- 445
    [958] = 'Diamond Shell',         -- 446

    -- RDM Crimson Duelist Spec
    [959] = 'Hex Volley',            -- 447
    [960] = 'Crimson Fleche',        -- 448

    -- DNC Mirage Sentinel Spec
    [961] = 'Pirouette Deflect',     -- 449
    [962] = 'Dazzling Cadence',      -- 450

    -- DRK Dreadnought Spec
    [961] = 'Abyssal Cleave',        -- 449
    [962] = 'Dread Bastion',         -- 450

    -- PUP Vanguard Spec
    [963] = 'Aegis Protocol',        -- 451
    [964] = 'Gyro Slam',             -- 452
}

------------------------------------------------------------------------------------------------------
-- Returns the custom ability name if defined for OverlordsXI.
------------------------------------------------------------------------------------------------------
---@param id integer
---@return string|nil
------------------------------------------------------------------------------------------------------
Overlords.GetAbilityName = function(id)
    if not id then
        return nil
    end

    return Overlords.CustomAbilities[id]
end

------------------------------------------------------------------------------------------------------
-- Finds the party/alliance owner name for an active pet by display name.
------------------------------------------------------------------------------------------------------
---@param petName string
---@return string|nil
------------------------------------------------------------------------------------------------------
Overlords.FindAffiliatePetOwner = function(petName)
    if not petName or petName == '' then
        return nil
    end

    local memMgr    = AshitaCore and AshitaCore:GetMemoryManager()
    local partyMgr  = memMgr and memMgr:GetParty()
    local entityMgr = memMgr and memMgr:GetEntity()

    if not partyMgr or not entityMgr then
        return nil
    end

    for slot = 0, 17 do
        if partyMgr:GetMemberIsActive(slot) == 1 then
            local ownerIndex = partyMgr:GetMemberTargetIndex(slot)
            if ownerIndex and ownerIndex > 0 then
                local petIndex = entityMgr:GetPetTargetIndex(ownerIndex)
                if petIndex and petIndex > 0 then
                    if entityMgr:GetName(petIndex) == petName then
                        return partyMgr:GetMemberName(slot)
                    end
                end
            end
        end
    end

    return nil
end

------------------------------------------------------------------------------------------------------
-- Checks whether a ranged ENDRAIN additional effect is actually from Bloody Bolt rather than
-- OverlordsXI's Drain Daze / chakram mechanics.
------------------------------------------------------------------------------------------------------
---@param audits table
---@return boolean
------------------------------------------------------------------------------------------------------
Overlords.IsBloodyBoltEndrain = function(audits)
    if Debug and Debug.Enabled and Debug.Unit and Debug.Unit.Active then
        return true
    end

    if not audits or not audits.player_name or audits.pet_name then
        return false
    end

    local actorJob = Ashita.Party.GetMember(audits.player_name)
    if actorJob and (actorJob.main == Ashita.Jobs.DNC or actorJob.sub == Ashita.Jobs.DNC) then
        return false
    end

    if Ashita.Mob.IsMe(audits.player_name) then
        local inv    = AshitaCore:GetMemoryManager():GetInventory()
        local resMgr = AshitaCore:GetResourceManager()
        if inv and resMgr then
            -- Slot 3 is the Ammo equipment slot. Chakram/throwing users have no crossbow bolt equipped here.
            local eq = inv:GetEquippedItem(3)
            if not eq or not eq.Index or eq.Index == 0 then
                return false
            end

            local bagId   = math.floor(eq.Index / 256)
            local itemIdx = eq.Index % 256
            if itemIdx > 0 then
                local item = inv:GetContainerItem(bagId, itemIdx)
                if not item or not item.Id or item.Id == 0 or item.Id == 65535 then
                    return false
                end

                local itemData = resMgr:GetItemById(item.Id)
                local itemName = itemData and itemData.Name and (itemData.Name[3] or itemData.Name[1])
                if itemName and itemName ~= 'Bloody Bolt' then
                    return false
                end
            end
        end
    end

    return true
end

------------------------------------------------------------------------------------------------------
-- Ensures a DoT effect has at least 1 recorded attempt so it renders in Focus Magic / Pet subtabs
-- even when the initial cast was missed or triggered by a non-spell/pet effect.
------------------------------------------------------------------------------------------------------
---@param audits     table
---@param trackable  DB.Trackable
---@param effectName string
------------------------------------------------------------------------------------------------------
local ensureDotVisibility = function(audits, trackable, effectName)
    local playerName = audits.player_name
    local targetName = audits.target_name
    local petName    = audits.pet_name

    local existingAttempts
    if petName then
        existingAttempts = DB.PetCatalog.Get(playerName, petName, trackable, effectName, DB.Metric.ATTEMPTS_ON_USE, targetName)
    else
        existingAttempts = DB.Catalog.Get(playerName, trackable, effectName, DB.Metric.ATTEMPTS_ON_USE, targetName)
    end

    if existingAttempts == 0 then
        DB.Data.Update(DB.UpdateMode.INC, 1, audits, trackable, DB.Metric.HITS_ON_USE)
        DB.Data.Update(DB.UpdateMode.INC, 1, audits, trackable, DB.Metric.ATTEMPTS_ON_USE)
        DB.Catalog.UpdateMetric(DB.UpdateMode.INC, 1, audits, trackable, effectName, DB.Metric.HITS_ON_USE)
        DB.Catalog.UpdateMetric(DB.UpdateMode.INC, 1, audits, trackable, effectName, DB.Metric.ATTEMPTS_ON_USE)
    end
end

------------------------------------------------------------------------------------------------------
-- Parses OverlordsXI's 0x017 MESSAGE_SYSTEM_3 DoT damage log messages into Metrics' database.
-- Server format: "<Caster>'s <Effect> deals <Amount> point(s) of damage to <Target>."
------------------------------------------------------------------------------------------------------
---@param data string
------------------------------------------------------------------------------------------------------
Overlords.HandleChatPacket = function(data)
    if not data or #data < 25 then
        return nil
    end

    local msgType = string.byte(data, 5)
    if msgType ~= MESSAGE_SYSTEM_3 then
        return nil
    end

    local msg = string.sub(data, 24):match('^([^%z]*)')
    if not msg or msg == '' then
        return nil
    end

    local casterName, effectName, dmgStr, targetName = msg:match("^(.-)'s (.-) deals (%d+) points? of damage to (.+)%.$")
    if not casterName then
        return nil
    end

    local damage = tonumber(dmgStr)
    if not damage or damage <= 0 then
        return nil
    end

    Ashita.Party.Refresh()

    local audits
    local trackable
    local overall

    if Ashita.Party.IsAffiliate(casterName) then
        audits =
        {
            player_name = casterName,
            target_name = targetName,
        }
        trackable = DB.Trackable.SPELLS_DOT
        overall   = DB.Trackable.SPELLS_OVERALL
    else
        local ownerName = Overlords.FindAffiliatePetOwner(casterName)
        if not ownerName then
            return nil
        end

        audits =
        {
            player_name = ownerName,
            target_name = targetName,
            pet_name    = casterName,
        }
        trackable = DB.Trackable.PET_DOT
        overall   = DB.Trackable.PET_OVERALL
    end

    Timers.Reset(Timers.Types.AUTOPAUSE)
    Timers.Unpause(Timers.Types.PARSE)

    DB.Lists.AddToInitializedMobs(targetName)

    H.Offense.CatalogHit(audits, trackable, damage, effectName)
    H.Offense.Hit(audits, overall, damage)
    ensureDotVisibility(audits, trackable, effectName)
end
