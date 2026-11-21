#pragma once
#include "crystaljobs.h"
#include "labels.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

namespace crystaljobs {

struct ActionRecord {
    uint8_t  job = 0;
    uint8_t  branch = 0;
    uint16_t action_id = 0;
    uint32_t kind = 0;
    uint16_t icon_id = 0xFFFFu;
    uint16_t icon_id_v2 = 0xFFFFu;
    char     name[80]{};
    char     description[192]{};
};

struct ActionKey {
    uint8_t  job;
    uint8_t  branch;
    uint32_t kind;
    uint16_t action_id;
};

inline bool action_key_less(const ActionRecord& a, const ActionKey& b) noexcept {
    if (a.job != b.job) return a.job < b.job;
    if (a.branch != b.branch) return a.branch < b.branch;
    if (a.kind != b.kind) return a.kind < b.kind;
    return a.action_id < b.action_id;
}

inline bool action_record_less(const ActionRecord& a, const ActionRecord& b) noexcept {
    return action_key_less(a, ActionKey{b.job, b.branch, b.kind, b.action_id});
}

inline bool action_key_equal(const ActionRecord& a, const ActionKey& b) noexcept {
    return a.job == b.job && a.branch == b.branch && a.kind == b.kind && a.action_id == b.action_id;
}

inline bool valid_action_kind(uint32_t kind) noexcept {
    return kind == CRYSTALJOBS_ACTION_SPELL ||
           kind == CRYSTALJOBS_ACTION_ABILITY ||
           kind == CRYSTALJOBS_ACTION_WEAPONSKILL;
}

inline bool valid_action_id(uint32_t kind, uint16_t id) noexcept {
    if (kind == CRYSTALJOBS_ACTION_SPELL) return id <= 1023u;
    if (kind == CRYSTALJOBS_ACTION_WEAPONSKILL) return id <= 511u;
    if (kind == CRYSTALJOBS_ACTION_ABILITY) return id <= 2047u;
    return false;
}

inline void copy_cstr_bounded(char* dst, size_t dst_size, const char* src, size_t src_max) noexcept {
    if (dst == nullptr || dst_size == 0) return;
    dst[0] = '\0';
    if (src == nullptr) return;
    size_t in = 0;
    size_t out = 0;
    const size_t out_limit = dst_size - 1;
    while (in < src_max && src[in] != '\0' && out < out_limit) {
        const unsigned char ch = static_cast<unsigned char>(src[in]);
        // Normalize common UTF-8 punctuation (curly quotes, dashes, ellipsis) to
        // single-byte ASCII so FFXI's legacy Shift-JIS/helpwind renderer never
        // misinterprets high bytes as multibyte/control sequences.
        if (ch == 0xE2u && in + 2 < src_max && static_cast<unsigned char>(src[in + 1]) == 0x80u) {
            const unsigned char b2 = static_cast<unsigned char>(src[in + 2]);
            if (b2 == 0x98u || b2 == 0x99u) {
                dst[out++] = '\'';
                in += 3;
                continue;
            }
            if (b2 == 0x9Cu || b2 == 0x9Du) {
                dst[out++] = '"';
                in += 3;
                continue;
            }
            if (b2 == 0x93u || b2 == 0x94u) {
                dst[out++] = '-';
                in += 3;
                continue;
            }
            if (b2 == 0xA6u) {
                for (int k = 0; k < 3 && out < out_limit; ++k) dst[out++] = '.';
                in += 3;
                continue;
            }
        }
        // Reject control characters (< 0x20) and remaining non-ASCII/DEL bytes (>= 0x7F).
        if (ch < 0x20u || ch >= 0x7Fu) {
            if (out == 0 || dst[out - 1] != ' ') dst[out++] = ' ';
            // Skip UTF-8 continuation bytes so one multibyte char becomes at most one space.
            ++in;
            while (in < src_max && (static_cast<unsigned char>(src[in]) & 0xC0u) == 0x80u) ++in;
            continue;
        }
        dst[out++] = static_cast<char>(ch);
        ++in;
    }
    while (out > 0 && dst[out - 1] == ' ') --out;
    dst[out] = '\0';
}

// Bound single-line helpwind description text so long Soul descriptions never
// overflow or overlap adjacent UI elements in FFXI's top help bar.
inline bool format_action_description(const char* full, char* output,
                                      size_t capacity, size_t max_chars) noexcept {
    if (!full || !output || capacity < 8 || max_chars < 16 || max_chars >= capacity) return false;
    size_t length = 0;
    while (length < capacity && full[length] != '\0') ++length;
    if (length >= capacity) return false;
    if (length <= max_chars) {
        std::memcpy(output, full, length + 1);
        return true;
    }
    size_t cut = max_chars - 3;
    // Prefer a clean word boundary when cutting.
    size_t word_cut = cut;
    while (word_cut > max_chars / 2 && full[word_cut] != ' ') --word_cut;
    if (word_cut > max_chars / 2) cut = word_cut;
    while (cut > 0 && full[cut - 1] == ' ') --cut;
    if (cut == 0) return false;
    std::memcpy(output, full, cut);
    std::memcpy(output + cut, "...", 4);
    return true;
}

inline bool validate_and_convert(const CrystalJobsActionEntry& in, ActionRecord& out) noexcept {
    if (in.size != sizeof(CrystalJobsActionEntry)) return false;
    if (in.job < 1 || in.job > 22 || !valid_branch(in.job, in.branch)) return false;
    if (!valid_action_kind(in.kind) || !valid_action_id(in.kind, in.action_id)) return false;

    out = {};
    out.job = in.job;
    out.branch = in.branch;
    out.action_id = in.action_id;
    out.kind = in.kind;
    out.icon_id = in.icon_id;
    out.icon_id_v2 = in.icon_id_v2;
    copy_cstr_bounded(out.name, sizeof(out.name), in.name, sizeof(in.name));
    copy_cstr_bounded(out.description, sizeof(out.description), in.description, sizeof(in.description));

    // Must override at least one presentation field.
    const bool has_name = out.name[0] != '\0';
    const bool has_desc = out.description[0] != '\0';
    const bool has_icon = out.icon_id != 0xFFFFu || out.icon_id_v2 != 0xFFFFu;
    return has_name || has_desc || has_icon;
}

// Compact names only for narrow, stock FFXI Magic/JA/WS list rows.
// Full catalog strings, descriptions, target-selection banners, and gameplay
// dispatch are untouched. The width is set by the addon, not by Soul names.
// The native list font uses a legacy single-byte encoding; do not split a
// possible UTF-8 multibyte sequence at the cut.
inline bool compact_action_row_name(const char* full, char* output,
                                    size_t capacity, size_t max_chars) noexcept {
    if (!full || !output || capacity < 2 || max_chars < 8 || max_chars >= capacity) return false;
    size_t length = 0;
    while (length < capacity && full[length] != '\0') ++length;
    if (length >= capacity) return false;
    if (length <= max_chars) {
        std::memcpy(output, full, length + 1);
        return true;
    }
    // Preserve the meaningful action tier suffix (e.g. ": Ichi" / ": Ni")
    // and abbreviate its prefix with a period. This needs no per-Soul rules.
    size_t suffix = length;
    for (size_t i = 0; i + 1 < length; ++i) {
        if (full[i] == ':' && full[i + 1] == ' ') suffix = i;
    }
    if (suffix < length && length - suffix < max_chars / 2) {
        const size_t tail = length - suffix;
        // Reserve a consistent suffix slot so Ichi/Ni-style variants of
        // the same action don't appear with wildly different stem lengths.
        const size_t reserved_suffix = (tail < 6) ? 6 : tail;
        const size_t prefix_max = max_chars > reserved_suffix + 1
            ? max_chars - reserved_suffix - 1 : 0;
        if (prefix_max >= 3) {
            size_t end = prefix_max;
            while (end > 0 && (static_cast<unsigned char>(full[end]) & 0xC0u) == 0x80u) --end;
            if (end >= 3) {
                while (end && full[end - 1] == ' ') --end;
                std::memcpy(output, full, end);
                output[end] = '.';
                std::memcpy(output + end + 1, full + suffix, tail);
                output[end + 1 + tail] = '\0';
                return true;
            }
        }
    }
    // Generic no-suffix fallback. Mark abbreviated rows visibly.
    size_t end = max_chars - 3;
    while (end > 0 && (static_cast<unsigned char>(full[end]) & 0xC0u) == 0x80u) --end;
    if (end == 0) return false;
    std::memcpy(output, full, end);
    std::memcpy(output + end, "...", 4);
    return true;
}

class ActionCatalog {
public:
    static constexpr uint32_t kMaxEntries = 4096;

    bool replace_all(const CrystalJobsActionEntry* entries, uint32_t count) {
        if (count > kMaxEntries) return false;
        if (count > 0 && entries == nullptr) return false;
        std::vector<ActionRecord> next;
        next.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            ActionRecord rec;
            if (!validate_and_convert(entries[i], rec)) return false;
            next.push_back(rec);
        }
        std::sort(next.begin(), next.end(), action_record_less);
        // Reject duplicate (job, branch, kind, action_id) entries in a single atomic replace.
        for (size_t i = 1; i < next.size(); ++i) {
            if (action_key_equal(next[i - 1], ActionKey{next[i].job, next[i].branch, next[i].kind, next[i].action_id})) {
                return false;
            }
        }
        records_.swap(next);
        ++generation_;
        return true;
    }

    bool upsert(const CrystalJobsActionEntry& entry) {
        ActionRecord rec;
        if (!validate_and_convert(entry, rec)) return false;
        const ActionKey key{rec.job, rec.branch, rec.kind, rec.action_id};
        auto it = std::lower_bound(records_.begin(), records_.end(), key, action_key_less);
        if (it != records_.end() && action_key_equal(*it, key)) {
            *it = rec;
        } else {
            if (records_.size() >= kMaxEntries) return false;
            records_.insert(it, rec);
        }
        ++generation_;
        return true;
    }

    void clear() noexcept {
        records_.clear();
        ++generation_;
    }

    const ActionRecord* find(uint8_t job, uint8_t branch, uint32_t kind, uint16_t action_id) const noexcept {
        if (records_.empty() || job == 0 || branch == 0) return nullptr;
        const ActionKey key{job, branch, kind, action_id};
        auto it = std::lower_bound(records_.begin(), records_.end(), key, action_key_less);
        if (it != records_.end() && action_key_equal(*it, key)) {
            return &(*it);
        }
        return nullptr;
    }

    uint32_t count() const noexcept { return static_cast<uint32_t>(records_.size()); }
    uint32_t generation() const noexcept { return generation_; }

private:
    std::vector<ActionRecord> records_;
    uint32_t generation_ = 0;
};

enum class VisibilityDecision : uint8_t {
    Unmanaged = 0,
    Show      = 1,
    Hide      = 2,
};

struct VisibilityRecord {
    uint8_t  job = 0;
    uint8_t  branch = 0;
    uint8_t  min_effective_level = 1;
    uint8_t  rule = CRYSTALJOBS_VIS_RULE_UNLOCK;
    uint32_t kind = 0;
    uint16_t action_id = 0;
};

inline bool vis_key_less(const VisibilityRecord& a, const ActionKey& b) noexcept {
    if (a.job != b.job) return a.job < b.job;
    if (a.branch != b.branch) return a.branch < b.branch;
    if (a.kind != b.kind) return a.kind < b.kind;
    return a.action_id < b.action_id;
}

inline bool vis_record_less(const VisibilityRecord& a, const VisibilityRecord& b) noexcept {
    return vis_key_less(a, ActionKey{b.job, b.branch, b.kind, b.action_id});
}

inline bool vis_key_equal(const VisibilityRecord& a, const ActionKey& b) noexcept {
    return a.job == b.job && a.branch == b.branch && a.kind == b.kind && a.action_id == b.action_id;
}

inline bool validate_and_convert_visibility(const CrystalJobsVisibilityEntry& in, VisibilityRecord& out) noexcept {
    if (in.size != sizeof(CrystalJobsVisibilityEntry)) return false;
    if (in.job < 1 || in.job > 22 || !valid_branch(in.job, in.branch)) return false;
    if (!valid_action_kind(in.kind) || !valid_action_id(in.kind, in.action_id)) return false;
    if (in.min_effective_level < 1 || in.min_effective_level > 99) return false;
    if (in.rule != CRYSTALJOBS_VIS_RULE_UNLOCK && in.rule != CRYSTALJOBS_VIS_RULE_HIDDEN) return false;
    out = {};
    out.job = in.job;
    out.branch = in.branch;
    out.min_effective_level = in.min_effective_level;
    out.rule = in.rule;
    out.kind = in.kind;
    out.action_id = in.action_id;
    return true;
}

class VisibilityCatalog {
public:
    static constexpr uint32_t kMaxEntries = 4096;

    bool replace_all(const CrystalJobsVisibilityEntry* entries, uint32_t count) {
        if (count > kMaxEntries) return false;
        if (count > 0 && entries == nullptr) return false;
        std::vector<VisibilityRecord> next;
        next.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            VisibilityRecord rec;
            if (!validate_and_convert_visibility(entries[i], rec)) return false;
            next.push_back(rec);
        }
        std::sort(next.begin(), next.end(), vis_record_less);
        for (size_t i = 1; i < next.size(); ++i) {
            if (vis_key_equal(next[i - 1], ActionKey{next[i].job, next[i].branch, next[i].kind, next[i].action_id})) {
                return false;
            }
        }
        records_.swap(next);
        ++generation_;
        return true;
    }

    void clear() noexcept {
        records_.clear();
        ++generation_;
    }

    VisibilityDecision decide(uint8_t job, uint8_t branch, uint32_t kind, uint16_t action_id, uint8_t effective_level) const noexcept {
        if (records_.empty() || job == 0 || branch == 0 || effective_level == 0) return VisibilityDecision::Unmanaged;
        const ActionKey key{job, branch, kind, action_id};
        auto it = std::lower_bound(records_.begin(), records_.end(), key, vis_key_less);
        if (it == records_.end() || !vis_key_equal(*it, key)) return VisibilityDecision::Unmanaged;
        if (it->rule == CRYSTALJOBS_VIS_RULE_HIDDEN || effective_level < it->min_effective_level) {
            return VisibilityDecision::Hide;
        }
        return VisibilityDecision::Show;
    }

    uint32_t count() const noexcept { return static_cast<uint32_t>(records_.size()); }
    uint32_t generation() const noexcept { return generation_; }

private:
    std::vector<VisibilityRecord> records_;
    uint32_t generation_ = 0;
};

struct WeaponRuleRecord {
    uint8_t  job = 0;
    uint8_t  branch = 0;
    uint8_t  min_effective_level = 10;
    uint8_t  mode = CRYSTALJOBS_WEAPON_MODE_DUAL_1H;
    uint32_t main_skill_mask = 0;
    uint32_t sub_skill_mask = 0;
    uint16_t main_item_id = 0;
    uint16_t sub_item_id = 0;
};

inline bool validate_and_convert_weapon_rule(const CrystalJobsWeaponRule& in, WeaponRuleRecord& out) noexcept {
    if (in.size != sizeof(CrystalJobsWeaponRule)) return false;
    if (in.job < 1 || in.job > 22 || !valid_branch(in.job, in.branch)) return false;
    if (in.min_effective_level < 1 || in.min_effective_level > 99) return false;
    if (in.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_1H &&
        in.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_2H &&
        in.mode != CRYSTALJOBS_WEAPON_MODE_TWOHAND_SHIELD) return false;
    if (in.main_skill_mask == 0 || in.sub_skill_mask == 0) return false;
    out = {};
    out.job = in.job;
    out.branch = in.branch;
    out.min_effective_level = in.min_effective_level;
    out.mode = in.mode;
    out.main_skill_mask = in.main_skill_mask;
    out.sub_skill_mask = in.sub_skill_mask;
    out.main_item_id = in.main_item_id;
    out.sub_item_id = in.sub_item_id;
    return true;
}

class WeaponRuleCatalog {
public:
    static constexpr uint32_t kMaxEntries = 256;

    bool replace_all(const CrystalJobsWeaponRule* entries, uint32_t count) {
        if (count > kMaxEntries) return false;
        if (count > 0 && entries == nullptr) return false;
        std::vector<WeaponRuleRecord> next;
        next.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            WeaponRuleRecord rec;
            if (!validate_and_convert_weapon_rule(entries[i], rec)) return false;
            next.push_back(rec);
        }
        records_.swap(next);
        ++generation_;
        return true;
    }

    void clear() noexcept {
        records_.clear();
        ++generation_;
    }

    bool has_rules_for(uint8_t job, uint8_t branch) const noexcept {
        for (const auto& rec : records_) {
            if (rec.job == job && rec.branch == branch) return true;
        }
        return false;
    }

    bool allows_sub_weapon(uint8_t job, uint8_t branch, uint8_t effective_level,
                           uint16_t main_skill, uint16_t main_item_id,
                           uint16_t sub_skill, uint16_t sub_item_id) const noexcept {
        if (records_.empty() || job == 0 || branch == 0 || effective_level == 0) return false;
        if (main_skill == 0 || main_skill >= 32u || sub_skill == 0 || sub_skill >= 32u) return false;
        const uint32_t main_bit = 1u << main_skill;
        const uint32_t sub_bit = 1u << sub_skill;
        for (const auto& rec : records_) {
            if (rec.job != job || rec.branch != branch) continue;
            if (effective_level < rec.min_effective_level) continue;
            if (rec.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_1H && rec.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_2H) continue;
            if ((rec.main_skill_mask & main_bit) == 0) continue;
            if ((rec.sub_skill_mask & sub_bit) == 0) continue;
            if (rec.main_item_id != 0 && rec.main_item_id != main_item_id) continue;
            if (rec.sub_item_id != 0 && rec.sub_item_id != sub_item_id) continue;
            return true;
        }
        return false;
    }

    bool allows_dual_2h_menu_item(uint8_t job, uint8_t branch, uint8_t effective_level,
                                  uint16_t sub_skill, uint16_t sub_item_id) const noexcept {
        if (records_.empty() || job == 0 || branch == 0 || effective_level == 0) return false;
        if (sub_skill == 0 || sub_skill >= 32u) return false;
        const uint32_t sub_bit = 1u << sub_skill;
        for (const auto& rec : records_) {
            if (rec.job != job || rec.branch != branch) continue;
            if (effective_level < rec.min_effective_level) continue;
            if (rec.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_2H) continue;
            if ((rec.sub_skill_mask & sub_bit) == 0) continue;
            if (rec.sub_item_id != 0 && rec.sub_item_id != sub_item_id) continue;
            return true;
        }
        return false;
    }

    bool allows_2h_main_with_sub(uint8_t job, uint8_t branch, uint8_t effective_level,
                                 uint16_t main_skill, uint16_t main_item_id,
                                 uint16_t sub_skill, uint16_t sub_item_id) const noexcept {
        if (records_.empty() || job == 0 || branch == 0 || effective_level == 0) return false;
        if (main_skill == 0 || main_skill >= 32u || sub_skill == 0 || sub_skill >= 32u) return false;
        const uint32_t main_bit = 1u << main_skill;
        const uint32_t sub_bit = 1u << sub_skill;
        for (const auto& rec : records_) {
            if (rec.job != job || rec.branch != branch) continue;
            if (effective_level < rec.min_effective_level) continue;
            if (rec.mode != CRYSTALJOBS_WEAPON_MODE_DUAL_2H) continue;
            if ((rec.main_skill_mask & main_bit) == 0) continue;
            if ((rec.sub_skill_mask & sub_bit) == 0) continue;
            if (rec.main_item_id != 0 && rec.main_item_id != main_item_id) continue;
            if (rec.sub_item_id != 0 && rec.sub_item_id != sub_item_id) continue;
            return true;
        }
        return false;
    }

    uint32_t count() const noexcept { return static_cast<uint32_t>(records_.size()); }
    uint32_t generation() const noexcept { return generation_; }

private:
    std::vector<WeaponRuleRecord> records_;
    uint32_t generation_ = 0;
};

} // namespace crystaljobs
