#pragma once
#include <cstdint>
#include <cstring>

namespace crystaljobs {
constexpr uint32_t capability = 0x43525901;
constexpr uint32_t marker = 0x43525900;
constexpr uint32_t lease_ms = 2500;

inline const char* label_for(uint8_t job, uint8_t branch, bool full = false) noexcept {
    switch (job) {
        case 1: // WAR
            switch (branch) {
                case 1: return full ? "Commander" : "CDR";
                case 2: return full ? "Berserker" : "BRZ";
                case 3: return full ? "Spartan" : "SPT";
                default: return nullptr;
            }
        case 2: // MNK
            switch (branch) {
                case 1: return full ? "Sensei" : "SEN";
                case 2: return full ? "Chi Weaver" : "CWV";
                case 3: return full ? "Black Belt" : "BLK";
                default: return nullptr;
            }
        case 3: // WHM
            switch (branch) {
                case 1: return full ? "Bishop" : "BSH";
                case 2: return full ? "Zealot" : "ZEL";
                case 3: return full ? "Valkyrie" : "VLK";
                default: return nullptr;
            }
        case 4: // BLM
            switch (branch) {
                case 1: return full ? "Astromancer" : "AST";
                case 2: return full ? "Channeler" : "CHN";
                case 3: return full ? "Necromancer" : "NEC";
                default: return nullptr;
            }
        case 5: // RDM
            switch (branch) {
                case 1: return full ? "Crimson Duelist" : "DLS";
                case 2: return full ? "Royal Tactician" : "RYT";
                case 3: return full ? "Scarlet Weaver" : "SCW";
                default: return nullptr;
            }
        case 6: // THF
            switch (branch) {
                case 1: return full ? "Trickster" : "TRK";
                case 2: return full ? "Bandit" : "BND";
                case 3: return full ? "Phantom" : "PHN";
                default: return nullptr;
            }
        case 7: // PLD
            switch (branch) {
                case 1: return full ? "Templar" : "TMP";
                case 2: return full ? "Defender" : "DFN";
                case 3: return full ? "Oathbreaker" : "OTB";
                default: return nullptr;
            }
        case 8: // DRK
            switch (branch) {
                case 1: return full ? "Reaper" : "RPR";
                case 2: return full ? "Dreadnought" : "DRN";
                case 3: return full ? "Scourge" : "SCR";
                default: return nullptr;
            }
        case 9: // BST
            switch (branch) {
                case 1: return full ? "Untamed" : "UNT";
                case 2: return full ? "Soulbeast" : "SLB";
                case 3: return full ? "Beastspeaker" : "BSP";
                default: return nullptr;
            }
        case 10: // BRD
            switch (branch) {
                case 1: return full ? "Adventurer" : "ADV";
                case 2: return full ? "Musician" : "MUS";
                case 3: return full ? "Minstrel" : "MIN";
                default: return nullptr;
            }
        case 11: // RNG
            switch (branch) {
                case 1: return full ? "Sniper" : "SNP";
                case 2: return full ? "Huntsman" : "HNT";
                case 3: return full ? "Arcane Archer" : "ACA";
                default: return nullptr;
            }
        case 12: // SAM
            switch (branch) {
                case 1: return full ? "Ronin" : "RON";
                case 2: return full ? "Imperial Archer" : "IMP";
                case 3: return full ? "Warlord" : "WRL";
                default: return nullptr;
            }
        case 13: // NIN
            switch (branch) {
                case 1: return full ? "Shinobi" : "KRG";
                case 2: return full ? "Kagemusha" : "KGM";
                case 3: return full ? "Nightblade" : "NGB";
                default: return nullptr;
            }
        case 14: // DRG
            switch (branch) {
                case 1: return full ? "Lancer" : "LNC";
                case 2: return full ? "Skyborn" : "SKY";
                case 3: return full ? "Wyvernheart" : "WYV";
                default: return nullptr;
            }
        case 15: // SMN
            switch (branch) {
                case 1: return full ? "Primalist" : "PRM";
                case 2: return full ? "Celestial" : "CEL";
                case 3: return full ? "Herald" : "HLD";
                default: return nullptr;
            }
        case 16: // BLU
            switch (branch) {
                case 1: return full ? "Warmage" : "WMG";
                case 2: return full ? "Magus" : "MAG";
                case 3: return full ? "Azure Bastion" : "AZB";
                default: return nullptr;
            }
        case 17: // COR
            switch (branch) {
                case 1: return full ? "Flintlock" : "FLT";
                case 2: return full ? "Gambler" : "GMB";
                case 3: return full ? "Buccaneer" : "BUC";
                default: return nullptr;
            }
        case 18: // PUP
            switch (branch) {
                case 1: return full ? "Vanguard" : "VNG";
                case 2: return full ? "Pugilist" : "PGL";
                case 3: return full ? "Animist" : "ANM";
                default: return nullptr;
            }
        case 19: // DNC
            switch (branch) {
                case 1: return full ? "Mirage Sentinel" : "MRS";
                case 2: return full ? "Vampire" : "VMP";
                case 3: return full ? "Bladewheel" : "BLW";
                default: return nullptr;
            }
        case 20: // SCH
            switch (branch) {
                case 1: return full ? "Medic" : "MDC";
                case 2: return full ? "Sage" : "SAG";
                case 3: return full ? "Archivist" : "ARC";
                default: return nullptr;
            }
        case 21: // GEO
            switch (branch) {
                case 1: return full ? "Diviner" : "DIV";
                case 2: return full ? "Verdant" : "VRD";
                case 3: return full ? "Terramancer" : "TRM";
                default: return nullptr;
            }
        case 22: // RUN
            switch (branch) {
                case 1: return full ? "Spellblade" : "SPB";
                case 2: return full ? "Lifebinder" : "LFB";
                case 3: return full ? "Inquisitor" : "INQ";
                default: return nullptr;
            }
        default:
            return nullptr;
    }
}

inline bool has_soul_labels(uint8_t job) noexcept {
    return label_for(job, 1, false) != nullptr;
}

inline bool valid_branch(uint8_t job, uint8_t branch) noexcept {
    return branch != 0 && label_for(job, branch, false) != nullptr;
}

inline const char* label(uint8_t branch, bool full = false) noexcept {
    if (const char* custom = label_for(1, branch, full)) return custom;
    return full ? "Warrior" : "WAR";
}

inline uint32_t u32(const void* data) {
    uint32_t value;
    std::memcpy(&value, data, sizeof(value));
    return value;
}

struct State {
    uint32_t character = 0;
    uint32_t updated = 0;
    uint8_t job = 0, branch = 0;
    bool known = false;
    bool from_bridge = false;
    struct Entry { uint32_t character; uint8_t job; uint8_t branch; } rows[512]{};
    uint32_t next_row = 0;

    void clear_rows() { std::memset(rows, 0, sizeof(rows)); next_row = 0; }

    void update(const uint8_t* bytes, uint32_t size, uint32_t now) {
        if (size != 8 || bytes == nullptr || bytes[0] != 1 || bytes[1] > 1 || bytes[2] > 23 || bytes[3] > 7) {
            *this = {};
            return;
        }
        const uint32_t id = u32(bytes + 4);
        if (id != character) clear_rows();
        character = id;
        updated = now;
        known = bytes[1] == 1;
        job = bytes[2];
        branch = (known && valid_branch(job, bytes[3])) ? bytes[3] : 0;
        from_bridge = known;
    }

    bool alive(uint32_t now, uint32_t local_id, uint8_t local_job) const {
        return character != 0 && character == local_id && job != 0 && job == local_job && now - updated <= lease_ms;
    }

    void decoded(uint8_t* record) {
        const uint32_t tag = u32(record + 20), id = u32(record + 24);
        const bool ours = (tag & 0xffffff00u) == marker;
        // Consume our reserved-field extension before any legacy client consumer sees it.
        if (ours) std::memset(record + 20, 0, 4);
        const uint8_t branch_value = static_cast<uint8_t>(tag);
        const uint8_t row_job = record[32];
        const bool visible = (u32(record) & 0x140) == 0x140 && (u32(record + 48) & 0x4000) == 0;
        const uint8_t value = (ours && visible && valid_branch(row_job, branch_value)) ? branch_value : 0;
        for (auto& row : rows) {
            if (row.character == id && id != 0) { row.job = row_job; row.branch = value; return; }
        }
        if (id != 0 && value != 0) rows[next_row++ % 512] = {id, row_job, value};
    }

    uint8_t row_branch(const uint8_t* record) const {
        if (record == nullptr || (u32(record) & 0x140) != 0x140 || (u32(record + 48) & 0x4000) != 0) return 0;
        const uint32_t id = u32(record + 24);
        const uint8_t row_job = record[32];
        for (const auto& row : rows) {
            if (id != 0 && row.character == id) {
                return (row.job == row_job && valid_branch(row_job, row.branch)) ? row.branch : 0;
            }
        }
        return 0;
    }
};
}
