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
    size_t len = 0;
    const size_t limit = (dst_size - 1 < src_max) ? (dst_size - 1) : src_max;
    while (len < limit && src[len] != '\0') {
        const unsigned char ch = static_cast<unsigned char>(src[len]);
        // Reject control characters except space; sanitize to space if present.
        dst[len] = (ch < 0x20u && ch != '\t') ? ' ' : static_cast<char>(ch);
        ++len;
    }
    dst[len] = '\0';
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

} // namespace crystaljobs
