#pragma once
#include "labels.h"

namespace crystaljobs {
inline uint16_t u16(const void* bytes) { uint16_t value; std::memcpy(&value, bytes, 2); return value; }
inline uint32_t packet_size(const uint8_t* packet) { return (u16(packet) >> 9) * 4u; }
inline bool whole_packets(const uint8_t* bytes, uint32_t size) {
    uint32_t at = 0;
    while (at + 4 <= size) {
        const uint32_t length = packet_size(bytes + at);
        if (length == 0) break;
        if (length < 4 || length > size - at) return false;
        at += length;
    }
    while (at < size) if (bytes[at++] != 0) return false;
    return true;
}

struct Transport {
    uint32_t character = 0, last_query = 0;
    uint16_t pending = 0;
    uint32_t next_request = 0x8000;
    uint8_t job = 0;
    bool refresh = false;
    uint8_t timeouts = 0;
    uint32_t sent = 0, accepted = 0, rejected = 0;

    void reset(State& state) { character = 0; job = 0; pending = 0; refresh = false; timeouts = 0; state = {}; }

    static bool response(const uint8_t* packet, uint32_t size) {
        if (size != 64 || (u16(packet) & 0x1ff) != 0x1ff || packet_size(packet) != size ||
            std::memcmp(packet + 4, "CRYS", 4) != 0 || packet[8] != 1 || packet[9] > 4 ||
            packet[12] > 23 || packet[13] != 24 || packet[14] > 99 || packet[15] != 0) return false;
        for (uint32_t at = 16; at < 64; at += 2) {
            const uint8_t owned = packet[at], active = packet[at + 1];
            if ((owned & 1u) != 0 || active > 7 || (active != 0 && (owned & (1u << active)) == 0)) return false;
        }
        return true;
    }

    // Returns true only for this DLL's CRYS response namespace, consumed before native dispatch.
    bool incoming(const uint8_t* packet, uint32_t size, uint32_t now, State& state) {
        const uint16_t id = u16(packet) & 0x1ff;
        if (id == 0x00a && size > 0xb4) {
            reset(state);
            character = u32(packet + 4); job = packet[0xb4]; refresh = character != 0 && job > 0 && job <= 23;
        } else if (id == 0x00b) {
            reset(state);
        } else if (id == 0x061 && size > 0x0c && packet[0x0c] != job) {
            job = packet[0x0c]; pending = 0; state = {}; refresh = character != 0 && job > 0 && job <= 23;
        } else if (id == 0x1ff && size >= 12 && std::memcmp(packet + 4, "CRYS", 4) == 0) {
            const uint16_t request = u16(packet + 10);
            const bool valid = response(packet, size);
            if (request < 0x8000) { if (valid) refresh = true; return false; }
            if (request == pending && pending != 0 && now - last_query <= 2500) {
                pending = 0;
                if (valid && packet[9] == 0 && packet[12] == job && character != 0 && job >= 1 && job <= 23) {
                    const uint8_t active_branch = packet[16 + job * 2 + 1];
                    state.character = character; state.job = job; state.known = true; state.from_bridge = false;
                    state.branch = valid_branch(job, active_branch) ? active_branch : 0;
                    state.updated = now; timeouts = 0; ++accepted;
                } else { state.known = false; state.branch = 0; state.from_bridge = false; ++rejected; }
            } else ++rejected;
            return true;
        }
        return false;
    }

    void outgoing(const uint8_t* packet, State& state) { if ((u16(packet) & 0x1ff) == 0x00d) reset(state); }

    bool prepare(uint8_t* request, const uint8_t* counter, uint32_t now, const State* current_state = nullptr) {
        if (pending != 0 && now - last_query >= 2000) { pending = 0; ++timeouts; }
        if (current_state != nullptr && current_state->from_bridge && current_state->alive(now, character, job)) return false;
        if (character == 0 || !has_soul_labels(job) || timeouts >= 3 || next_request > 0xffff || (pending != 0 && now - last_query < 2000) ||
            (!refresh && now - last_query < 1000)) return false;
        std::memset(request, 0, 16);
        const uint16_t header = 0x11f | (4 << 9);
        std::memcpy(request, &header, 2); std::memcpy(request + 2, counter, 2);
        std::memcpy(request + 4, "CRYS", 4); request[8] = 1; request[12] = job;
        pending = static_cast<uint16_t>(next_request++);
        std::memcpy(request + 10, &pending, 2);
        last_query = now; refresh = false; ++sent;
        return true;
    }
};
}
