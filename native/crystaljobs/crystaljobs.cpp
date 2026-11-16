#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include "crystaljobs.h"
#include "transport.h"
#include "labels.h"
#include "layout.h"
#include <atomic>
#include <cstdio>

using namespace crystaljobs;
static SRWLOCK state_lock = SRWLOCK_INIT;
static State state;
static Transport transport;
static std::atomic<uint32_t> last_error{};
static std::atomic<bool> enabled{};
static std::atomic<uint32_t> decoded_rows{}, short_draws{}, full_lookups{}, item_lookups{};
using Lookup = const char* (__cdecl*)(int, int);
using Decode = void* (__cdecl*)(const uint8_t*, uint8_t*, int);
using Encode = int (__cdecl*)(const void*, uint8_t*);
using NativeText = int (__cdecl*)(int, int, const char*, uint32_t, float, float, int);
static Lookup original_lookup;
static Decode original_decode;
static Encode original_encode;
static NativeText native_text;
static uintptr_t original_sprite;
#ifdef CRYSTALJOBS_SELFTEST
static bool selftest_alive;
#endif

static bool alive() noexcept {
#ifdef CRYSTALJOBS_SELFTEST
    return selftest_alive;
#endif
    if (!enabled.load()) return false;
    AcquireSRWLockShared(&state_lock);
    const bool valid = state.alive(GetTickCount(), transport.character, transport.job);
    ReleaseSRWLockShared(&state_lock);
    return valid;
}

static bool session_alive() noexcept {
#ifdef CRYSTALJOBS_SELFTEST
    return selftest_alive;
#else
    if (!enabled.load()) return false;
    AcquireSRWLockShared(&state_lock);
    const bool valid = transport.character != 0 && transport.job >= 1 && transport.job <= 23;
    ReleaseSRWLockShared(&state_lock);
    return valid;
#endif
}

static const char* __cdecl item_label(int table, int job) noexcept {
    if (table == 2 && job >= 1 && job <= 23 && alive()) {
        AcquireSRWLockShared(&state_lock);
        const uint8_t branch = (state.known && state.job == static_cast<uint8_t>(job)) ? state.branch : 0;
        ReleaseSRWLockShared(&state_lock);
        if (const char* custom = label_for(static_cast<uint8_t>(job), branch, false)) {
            ++item_lookups;
            return custom;
        }
    }
    return original_lookup(table, job);
}

static int __cdecl encode_request(const void* filters, uint8_t* payload) noexcept {
    const int result = original_encode(filters, payload);
    if (session_alive()) {
        std::memcpy(payload - 4, &capability, 4);
        AcquireSRWLockExclusive(&state_lock);
        state.clear_rows();
        ReleaseSRWLockExclusive(&state_lock);
    }
    return result;
}

static void* __cdecl decode_row(const uint8_t* input, uint8_t* output, int flags) noexcept {
    void* result = original_decode(input, output, flags);
    AcquireSRWLockExclusive(&state_lock);
    if (enabled.load()) state.decoded(output);
    else if ((u32(output + 20) & 0xffffff00u) == marker) std::memset(output + 20, 0, 4);
    ReleaseSRWLockExclusive(&state_lock);
    ++decoded_rows;
    return result;
}

static uint8_t branch_for(const uint8_t* row) noexcept {
    if (!session_alive()) return 0;
    AcquireSRWLockShared(&state_lock);
    const uint8_t branch = state.row_branch(row);
    ReleaseSRWLockShared(&state_lock);
    return branch;
}

struct SpriteArgs { int x, y; float scale_x, scale_y; uint32_t color; int center, first, count; };
static_assert(sizeof(SpriteArgs) == 32);

static bool __stdcall draw_branch(const uint8_t* row, const SpriteArgs* args) noexcept {
    const uint8_t branch = branch_for(row);
    if (branch == 0 || row == nullptr) return false;
    const char* custom = label_for(row[32], branch, false);
    if (custom == nullptr) return false;
    // Fit the native font into the existing 23-pixel job sprite column.
    native_text(args->x, args->y, custom, args->color, 0.75f * args->scale_x, 0.75f * args->scale_y, 0);
    ++short_draws;
    return true;
}

static const char* __stdcall full_branch(const uint8_t* row, int table, int job) noexcept {
    if (table == 18 && row != nullptr && job >= 1 && job <= 23 && row[32] == static_cast<uint8_t>(job)) {
        const uint8_t branch = branch_for(row);
        if (const char* custom = label_for(static_cast<uint8_t>(job), branch, true)) {
            ++full_lookups;
            return custom;
        }
    }
    return original_lookup(table, job);
}

// Each adapter replaces a CALL, preserving all saved registers and the original callee's stack cleanup.
static __declspec(naked) void normal_sprite_hook() {
    __asm {
        pushad
        lea eax, [esp + 36]
        push eax
        push ebp
        call draw_branch
        test al, al
        jz stock
        popad
        ret 32
    stock:
        popad
        jmp dword ptr [original_sprite]
    }
}

static __declspec(naked) void master_sprite_hook() {
    __asm {
        pushad
        lea eax, [esp + 36]
        push eax
        push edi
        call draw_branch
        test al, al
        jz stock
        popad
        ret 32
    stock:
        popad
        jmp dword ptr [original_sprite]
    }
}

static __declspec(naked) void full_job_hook() {
    __asm {
        pushad
        mov eax, [esp + 40]
        mov edx, [esp + 36]
        push eax
        push edx
        push esi
        call full_branch
        mov [esp + 28], eax
        popad
        ret
    }
}

using MapDecode = int (__cdecl*)(uint8_t*, uint32_t, uintptr_t, uintptr_t, const uint8_t*, uint32_t);
using MapEncode = int (__cdecl*)(const uint8_t*, uint32_t, uint8_t*, uint32_t, uintptr_t);
static MapDecode original_map_decode;
static MapEncode original_map_encode;

static uint32_t received_packets(uint8_t* packets, uint32_t length, uint32_t now) {
    if (!whole_packets(packets, length)) return length;
    uint32_t at = 0;
    while (at + 4 <= length) {
        const uint32_t size = packet_size(packets + at);
        if (size == 0) break;
        bool consume;
        if (enabled.load()) {
            AcquireSRWLockExclusive(&state_lock);
            consume = transport.incoming(packets + at, size, now, state);
            ReleaseSRWLockExclusive(&state_lock);
        } else {
            consume = (u16(packets + at) & 0x1ff) == 0x1ff && size >= 12 &&
                std::memcmp(packets + at + 4, "CRYS", 4) == 0 && u16(packets + at + 10) >= 0x8000;
        }
        if (consume) {
            std::memmove(packets + at, packets + at + size, length - at - size);
            length -= size;
        } else at += size;
    }
    return length;
}

static int __cdecl map_decode(uint8_t* output, uint32_t capacity, uintptr_t context, uintptr_t tree, const uint8_t* wire, uint32_t length) noexcept {
    const int result = original_map_decode(output, capacity, context, tree, wire, length);
    if (result <= 28 || static_cast<uint32_t>(result) > capacity || result > 10000) return result;
    return 28 + static_cast<int>(received_packets(output + 28, result - 28, GetTickCount()));
}

static int __cdecl map_encode(const uint8_t* packets, uint32_t length, uint8_t* output, uint32_t capacity, uintptr_t table) noexcept {
    if (!enabled.load() || length < 4 || length > 10000 || !whole_packets(packets, length))
        return original_map_encode(packets, length, output, capacity, table);
    uint8_t combined[10016];
    uint32_t at = 0;
    AcquireSRWLockExclusive(&state_lock);
    while (at + 4 <= length) {
        const uint32_t size = packet_size(packets + at);
        if (size == 0) break;
        transport.outgoing(packets + at, state);
        at += size;
    }
    const uint32_t room = capacity == 0 ? 0 : (capacity - 1) / 3 * 2;
    const bool append = at >= 4 && length + 16 <= room && length + 16 <= 10000 &&
        transport.prepare(combined + at, packets + 2, GetTickCount(), &state);
    ReleaseSRWLockExclusive(&state_lock);
    if (!append) return original_map_encode(packets, length, output, capacity, table);
    std::memcpy(combined, packets, at);
    std::memcpy(combined + at + 16, packets + at, length - at);
    const int result = original_map_encode(combined, length + 16, output, capacity, table);
    if (result < 0) {
        AcquireSRWLockExclusive(&state_lock);
        transport.pending = 0;
        transport.refresh = true;
        ReleaseSRWLockExclusive(&state_lock);
    }
    return result;
}

struct Patch {
    uintptr_t rva;
    void* replacement;
    uint8_t original[5]{}, installed[5]{};
    uint8_t* site = nullptr;

    static bool compare_exchange(uint8_t* operand, uint32_t expected, uint32_t desired) {
        uint8_t exchanged;
        __asm {
            mov edx, operand
            mov eax, expected
            mov ecx, desired
            lock cmpxchg dword ptr [edx], ecx
            sete al
            mov exchanged, al
        }
        return exchanged != 0;
    }
    static bool write(uint8_t* target, const uint8_t* expected, const uint8_t* desired) {
        if (target[0] != 0xe8 || expected[0] != 0xe8 || desired[0] != 0xe8 ||
            (reinterpret_cast<uintptr_t>(target + 1) & 63) > 60) return false;
        DWORD protection, discarded;
        if (!VirtualProtect(target, 5, PAGE_EXECUTE_READWRITE, &protection)) return false;
        const bool exchanged = target[0] == 0xe8 && compare_exchange(target + 1, u32(expected + 1), u32(desired + 1));
        const bool opcode_intact = target[0] == 0xe8;
        const bool flushed = FlushInstructionCache(GetCurrentProcess(), target, 5) != 0;
        const bool restored = VirtualProtect(target, 5, protection, &discarded) != 0;
        return exchanged && opcode_intact && flushed && restored;
    }
    bool install(uint8_t* base) {
        if (site != nullptr) return std::memcmp(site, installed, 5) == 0;
        site = base + rva;
        if (*site != 0xe8) { site = nullptr; return false; }
        std::memcpy(original, site, 5);
        installed[0] = 0xe8;
        const uint32_t relative = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(replacement) - reinterpret_cast<uintptr_t>(site + 5));
        std::memcpy(installed + 1, &relative, 4);
        if (write(site, original, installed)) return true;
        write(site, installed, original);
        return false;
    }
    bool restore() {
        if (site == nullptr) return true;
        if (std::memcmp(site, original, 5) == 0) { site = nullptr; return true; }
        const bool ours = std::memcmp(site, installed, 5) == 0;
        const bool restored = ours && write(site, installed, original);
        site = nullptr;
        return restored;
    }
};

static Patch patches[] = {
    {0xD8CCD, reinterpret_cast<void*>(&encode_request)},
    {0xE2282, reinterpret_cast<void*>(&decode_row)},
    {0x13C302, reinterpret_cast<void*>(&item_label)},
    {0x1CBD4C, reinterpret_cast<void*>(&normal_sprite_hook)},
    {0x1CC086, reinterpret_cast<void*>(&master_sprite_hook)},
    {0x1DEE6D, reinterpret_cast<void*>(&full_job_hook)},
    {0x1DEEFB, reinterpret_cast<void*>(&full_job_hook)},
    {0xFA795, reinterpret_cast<void*>(&map_decode)},
    {0xDD5F6, reinterpret_cast<void*>(&map_encode)},
};

static bool host_detour(uint8_t* entry, const uint8_t* expected, size_t length, size_t stolen, HMODULE host) noexcept {
    if (host == nullptr || entry[0] != 0xe9 || stolen < 5 || stolen >= length) return false;
    for (size_t at = 5; at < stolen; ++at) if (entry[at] != 0x90) return false;
    if (std::memcmp(entry + stolen, expected + stolen, length - stolen) != 0) return false;
    const uintptr_t target = reinterpret_cast<uintptr_t>(entry + 5) + u32(entry + 1);
    MEMORY_BASIC_INFORMATION region{};
    if (VirtualQuery(reinterpret_cast<void*>(target), &region, sizeof(region)) != sizeof(region) ||
        region.AllocationBase != host || region.Type != MEM_IMAGE || region.State != MEM_COMMIT || (region.Protect & PAGE_GUARD) != 0) return false;
    const DWORD protection = region.Protect & 0xff;
    return protection == PAGE_EXECUTE || protection == PAGE_EXECUTE_READ || protection == PAGE_EXECUTE_READWRITE || protection == PAGE_EXECUTE_WRITECOPY;
}

static bool supported(uint8_t* base) noexcept {
    __try {
        if (reinterpret_cast<uintptr_t>(base) != 0x10000000) return false;
        const auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 0x1000) return false;
        const auto* pe = reinterpret_cast<IMAGE_NT_HEADERS32*>(base + dos->e_lfanew);
        if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
            pe->FileHeader.TimeDateStamp != 0x6ae818b4 || pe->OptionalHeader.SizeOfImage != 0xc17000) return false;
        for (const auto& signature : signatures) {
            if ((signature.rva == 0xDD6C0 || signature.rva == 0xDF7C0) && host_detour(base + signature.rva,
                signature.bytes, sizeof(signature.bytes), signature.rva == 0xDD6C0 ? 10 : 5, GetModuleHandleW(L"Ashita.dll"))) continue;
            size_t skip = 0;
            for (const auto& patch : patches) {
                if (patch.rva == signature.rva && patch.site != nullptr && std::memcmp(patch.site, patch.installed, 5) == 0) skip = 5;
            }
            if (std::memcmp(base + signature.rva + skip, signature.bytes + skip, sizeof(signature.bytes) - skip) != 0) return false;
        }
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

static SRWLOCK lifecycle_lock = SRWLOCK_INIT;
static bool ever_started;

extern "C" uint32_t __stdcall CrystalJobsShutdown() {
    AcquireSRWLockExclusive(&lifecycle_lock);
    enabled.store(false);
    AcquireSRWLockExclusive(&state_lock);
    transport.reset(state);
    ReleaseSRWLockExclusive(&state_lock);
    uint32_t failure = 0;
    for (size_t index = sizeof(patches) / sizeof(*patches); index-- > 0;) {
        auto& patch = patches[index];
        // Late high-ID replies must still be consumed after their last request was sent.
        if (ever_started && (patch.rva == 0xFA795 || patch.rva == 0xE2282) && patch.site != nullptr && std::memcmp(patch.site, patch.installed, 5) == 0) continue;
        if (!patch.restore()) failure = 3;
    }
    last_error.store(failure);
    ReleaseSRWLockExclusive(&lifecycle_lock);
    return failure;
}

extern "C" uint32_t __stdcall CrystalJobsInitialize() {
    AcquireSRWLockExclusive(&lifecycle_lock);
    if (enabled.load()) { ReleaseSRWLockExclusive(&lifecycle_lock); return 0; }
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(L"FFXiMain.dll"));
    if (!supported(base)) {
        last_error.store(1); ReleaseSRWLockExclusive(&lifecycle_lock); return 1;
    }
    original_lookup = reinterpret_cast<Lookup>(base + 0x1544C0);
    original_decode = reinterpret_cast<Decode>(base + 0x106300);
    original_encode = reinterpret_cast<Encode>(base + 0x104330);
    native_text = reinterpret_cast<NativeText>(base + 0x1CAD80);
    original_sprite = reinterpret_cast<uintptr_t>(base + 0x121110);
    original_map_decode = reinterpret_cast<MapDecode>(base + 0xDD6C0);
    original_map_encode = reinterpret_cast<MapEncode>(base + 0xDF7C0);
    HMODULE pinned;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&normal_sprite_hook), &pinned)) {
        last_error.store(2); ReleaseSRWLockExclusive(&lifecycle_lock); return 2;
    }
    for (auto& patch : patches) {
        if (!patch.install(base)) {
            ReleaseSRWLockExclusive(&lifecycle_lock);
            const uint32_t failure = CrystalJobsShutdown() == 0 ? 2 : 3;
            last_error.store(failure); return failure;
        }
    }
    AcquireSRWLockExclusive(&state_lock);
    transport.reset(state);
    ReleaseSRWLockExclusive(&state_lock);
    ever_started = true;
    last_error.store(0);
    enabled.store(true);
    ReleaseSRWLockExclusive(&lifecycle_lock);
    return 0;
}

extern "C" uint32_t __stdcall CrystalJobsSetState(const uint8_t* bytes, uint32_t size) {
    if (bytes == nullptr || size != 8 || bytes[0] != 1 || bytes[1] > 1 || bytes[2] > 23 || bytes[3] > 7 || !enabled.load()) return 1;
    AcquireSRWLockExclusive(&state_lock);
    const uint32_t id = u32(bytes + 4);
    if (id != 0 && bytes[2] >= 1 && bytes[2] <= 23 && (transport.character == 0 || transport.character == id)) {
        transport.character = id;
        transport.job = bytes[2];
    }
    const bool valid = id == transport.character && bytes[2] == transport.job && id != 0;
    if (valid) state.update(bytes, size, GetTickCount());
    else if (id == 0 && bytes[1] == 0) { state.known = false; state.branch = 0; state.from_bridge = false; }
    ReleaseSRWLockExclusive(&state_lock);
    return valid ? 0 : 1;
}

extern "C" uint32_t __stdcall CrystalJobsGetStatus(CrystalJobsStatus* output, uint32_t size) {
    if (output == nullptr || size < sizeof(*output)) return 1;
    CrystalJobsStatus status{};
    status.size = sizeof(status); status.version = 1;
    AcquireSRWLockShared(&lifecycle_lock);
    for (const auto& patch : patches) if (patch.site != nullptr && std::memcmp(patch.site, patch.installed, 5) == 0) ++status.hooks;
    if (enabled.load() && status.hooks != 9) { enabled.store(false); last_error.store(3); }
    status.enabled = enabled.load();
    ReleaseSRWLockShared(&lifecycle_lock);
    AcquireSRWLockShared(&state_lock);
    status.character_id = transport.character; status.job = transport.job;
    status.known = status.enabled && state.known && state.alive(GetTickCount(), transport.character, transport.job); status.branch = status.known ? state.branch : 0;
    for (const auto& row : state.rows) if (row.character != 0 && row.branch != 0) ++status.search_rows;
    status.queries_sent = transport.sent; status.replies_accepted = transport.accepted; status.replies_rejected = transport.rejected;
    status.last_error = last_error.load();
    if (status.last_error == 0) status.last_error = transport.next_request > 0xffff ? 5 : transport.timeouts >= 3 ? 4 : 0;
    ReleaseSRWLockShared(&state_lock);
    status.decoded_rows = decoded_rows.load(); status.item_labels = item_lookups.load(); status.search_labels = short_draws.load(); status.full_labels = full_lookups.load();
    *output = status;
    return 0;
}
static_assert(sizeof(CrystalJobsStatus) == 68);
