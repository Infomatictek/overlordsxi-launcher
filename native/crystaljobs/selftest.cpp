#define CRYSTALJOBS_SELFTEST
#include "crystaljobs.cpp"
#include <cassert>

static uint8_t row_a[72]{}, row_b[72]{};
static uint32_t sprite_calls, text_calls;
static const char* last_text;
static int __cdecl fake_text(int x, int y, const char* text, uint32_t color, float sx, float sy, int center) {
    assert(x == 100 && y == 50 && color == 0x80808080 && sx == 0.75f && sy == 0.75f && center == 0);
    ++text_calls; last_text = text; return x;
}
static int __fastcall fake_sprite(void*, void*, int x, int y, float sx, float sy, uint32_t color, int center, int first, int count) {
    assert(x == 100 && y == 50 && sx == 1.0f && sy == 1.0f && color == 0x80808080 && center == 0 && first == 0 && count == 0);
    ++sprite_calls; return 1;
}
static const char* __cdecl fake_lookup(int table, int job) {
    assert(table == 18 || table == 2);
    if (table == 2) {
        switch (job) {
            case 1: return "WAR";
            case 2: return "MNK";
            case 4: return "BLM";
            case 19: return "DNC";
            case 20: return "SCH";
            case 22: return "RUN";
            default: return "OTH";
        }
    }
    return job == 1 ? "Warrior" : "Monk";
}

// Naked fixtures keep the row in the real caller's register without relying on a compiler frame pointer.
static __declspec(naked) bool sprite_abi(void*, const uint8_t*) {
    __asm {
        push ebp
        push ebx
        push esi
        push edi
        mov ebp, [esp + 24]
        mov edi, ebp
        mov ebx, 12345678h
        mov esi, 23456789h
        push 45678901h
        push 0
        push 0
        push 0
        push 80808080h
        push 3f800000h
        push 3f800000h
        push 50
        push 100
        mov ecx, 34567890h
        call dword ptr [esp + 56]
        xor eax, eax
        cmp dword ptr [esp], 45678901h
        jne failed
        cmp ebx, 12345678h
        jne failed
        cmp esi, 23456789h
        jne failed
        cmp edi, ebp
        jne failed
        cmp ebp, [esp + 28]
        jne failed
        mov eax, 1
    failed:
        add esp, 4
        pop edi
        pop esi
        pop ebx
        pop ebp
        ret
    }
}

static __declspec(naked) const char* full_abi(const uint8_t*, int) {
    __asm {
        push esi
        mov esi, [esp + 8]
        push dword ptr [esp + 12]
        push 18
        call full_job_hook
        add esp, 8
        cmp esi, [esp + 8]
        je good
        xor eax, eax
    good:
        pop esi
        ret
    }
}

static void make_row(uint8_t* row, uint32_t id, uint32_t tag, uint8_t job = 1, uint32_t privacy = 0) {
    std::memset(row, 0, 72);
    const uint32_t fields = 0x4140;
    std::memcpy(row, &fields, 4);
    std::memcpy(row + 20, &tag, 4);
    std::memcpy(row + 24, &id, 4);
    std::memcpy(row + 48, &privacy, 4);
    row[32] = job;
}

static void make_packet(uint8_t* bytes, uint16_t id, uint32_t size) {
    std::memset(bytes, 0, size);
    const uint16_t header = static_cast<uint16_t>(id | ((size / 4) << 9));
    std::memcpy(bytes, &header, 2);
}

static void make_reply(uint8_t* bytes, uint16_t request, uint8_t branch = 2, uint8_t job = 1, uint8_t lvl = 75) {
    make_packet(bytes, 0x1ff, 64);
    std::memcpy(bytes + 4, "CRYS", 4); bytes[8] = 1;
    std::memcpy(bytes + 10, &request, 2); bytes[12] = job; bytes[13] = 24;
    bytes[14] = lvl; bytes[15] = 0;
    bytes[16 + job * 2] = 14;
    bytes[16 + job * 2 + 1] = branch;
}

static int fake_decode_result;
static void* __cdecl fake_search_decode(const uint8_t* input, uint8_t* output, int flags) {
    assert(input == nullptr && flags == 1);
    return output + 72;
}
static int __cdecl fake_map_decode(uint8_t*, uint32_t capacity, uintptr_t context, uintptr_t tree, const uint8_t* wire, uint32_t length) {
    assert(capacity == 512 && context == 11 && tree == 12 && wire == nullptr && length == 13);
    return fake_decode_result;
}
static int __cdecl fake_map_encode(const uint8_t* bytes, uint32_t length, uint8_t* output, uint32_t capacity, uintptr_t table) {
    assert(capacity == 512 && table == 11 && length <= capacity);
    std::memcpy(output, bytes, length);
    return static_cast<int>(length);
}

static void transport_checks() {
    Transport model;
    State labels;
    uint8_t login[0xb8], request[16], reply[64];
    make_packet(login, 0x00a, sizeof(login));
    const uint32_t id = 100;
    std::memcpy(login + 4, &id, 4); login[0xb4] = 1;
    assert(whole_packets(login, sizeof(login)));
    model.incoming(login, sizeof(login), 1000, labels);
    const uint8_t counter[] = {0x34, 0x12};
    assert(model.prepare(request, counter, 1001));
    assert(u16(request) == (0x11f | (4 << 9)) && u16(request + 2) == 0x1234 && u16(request + 10) == 0x8000);
    assert(request[8] == 1 && request[9] == 0 && request[12] == 1);
    make_reply(reply, 0x8001);
    assert(model.incoming(reply, 64, 1100, labels) && !labels.known);
    make_reply(reply, 0x8000);
    assert(model.incoming(reply, 64, 1100, labels) && labels.known && labels.branch == 2);
    assert(!model.prepare(request, counter, 1500));
    assert(model.prepare(request, counter, 2100));
    make_reply(reply, model.pending); reply[19] = 4;
    model.incoming(reply, 64, 2200, labels); assert(!labels.known);
    make_reply(reply, 20); assert(!model.incoming(reply, 64, 2250, labels));
    assert(model.refresh);
    // Job 3 (WHM) has no soul crystals, so prepare() does not poll.
    uint8_t job[16]; make_packet(job, 0x061, 16); job[12] = 3;
    model.incoming(job, 16, 2300, labels); assert(model.job == 3 && !labels.known);
    assert(!model.prepare(request, counter, 2400));
    // Job 22 (RUN) has soul crystals (Inquisitor/Spellblade/Lifebinder), so prepare() polls with job=22.
    job[12] = 22;
    model.incoming(job, 16, 2450, labels); assert(model.job == 22 && !labels.known);
    assert(model.prepare(request, counter, 2500) && request[12] == 22);
    make_reply(reply, model.pending, 3, 22, 99);
    assert(model.incoming(reply, 64, 2550, labels) && labels.known && labels.job == 22 && labels.branch == 3);
    uint8_t logout[4]; make_packet(logout, 0x00d, 4);
    model.outgoing(logout, labels); assert(model.character == 0);
    model.incoming(login, sizeof(login), 3000, labels);
    assert(model.prepare(request, counter, 3000));
    assert(model.prepare(request, counter, 5000));
    assert(model.prepare(request, counter, 7000));
    assert(!model.prepare(request, counter, 9000) && model.timeouts == 3);
    model.incoming(login, sizeof(login), 10000, labels); model.next_request = 0xffff;
    assert(model.prepare(request, counter, 10000) && model.pending == 0xffff);
    make_reply(reply, 0xffff); model.incoming(reply, 64, 10100, labels);
    assert(!model.prepare(request, counter, 12000) && model.next_request == 0x10000);

    original_map_decode = &fake_map_decode; original_map_encode = &fake_map_encode;
    enabled.store(true);
    transport = {}; state = {};
    transport.incoming(login, sizeof(login), GetTickCount(), state);
    uint8_t stock[8], encoded[512]{};
    make_packet(stock, 0x015, 4); stock[2] = 0x34; stock[3] = 0x12;
    std::memset(stock + 4, 0, 4);
    assert(map_encode(stock, 8, encoded, 512, 11) == 24);
    assert(std::memcmp(stock, encoded, 4) == 0 && u16(encoded + 4) == (0x11f | (4 << 9)) && u16(encoded + 6) == 0x1234);
    assert(u32(encoded + 20) == 0);
    uint8_t decoded[512]; std::memset(decoded, 0x55, 28);
    make_packet(decoded + 28, 0x015, 4);
    make_reply(decoded + 32, transport.pending);
    make_packet(decoded + 96, 0x016, 4);
    fake_decode_result = 100;
    assert(map_decode(decoded, 512, 11, 12, nullptr, 13) == 36);
    assert(decoded[0] == 0x55 && decoded[27] == 0x55 && (u16(decoded + 28) & 0x1ff) == 0x015 && (u16(decoded + 32) & 0x1ff) == 0x016);
    assert(state.known && state.branch == 2);
    const uint32_t accepted = transport.accepted;
    make_reply(decoded + 28, 0x8001); decoded[28 + 13] = 2;
    make_packet(decoded + 92, 0x016, 4);
    decoded[94] = 0xff; decoded[95] = 0xff; // Valid counter; the declared size below is the malformed boundary.
    const uint16_t oversized = 0x016 | (100 << 9); std::memcpy(decoded + 92, &oversized, 2);
    fake_decode_result = 96;
    assert(map_decode(decoded, 512, 11, 12, nullptr, 13) == 96 && transport.accepted == accepted);
    enabled.store(false);
    make_reply(decoded + 28, 0x8002); fake_decode_result = 92;
    assert(map_decode(decoded, 512, 11, 12, nullptr, 13) == 28); // Shutdown's late-reply sink.
}

static void multi_job_checks() {
    // Check all 6 OverlordsXI soul jobs (WAR, MNK, BLM, DNC, SCH, RUN).
    assert(std::strcmp(label_for(1, 1, false), "CDR") == 0 && std::strcmp(label_for(1, 1, true), "Commander") == 0);
    assert(std::strcmp(label_for(1, 2, false), "BRZ") == 0 && std::strcmp(label_for(1, 2, true), "Berserker") == 0);
    assert(std::strcmp(label_for(1, 3, false), "GLA") == 0 && std::strcmp(label_for(1, 3, true), "Gladiator") == 0);
    assert(std::strcmp(label_for(2, 1, false), "SEN") == 0 && std::strcmp(label_for(2, 1, true), "Sensei") == 0);
    assert(std::strcmp(label_for(4, 1, false), "NEC") == 0 && std::strcmp(label_for(4, 1, true), "Necromancer") == 0);
    assert(std::strcmp(label_for(19, 1, false), "BLW") == 0 && std::strcmp(label_for(19, 1, true), "Bladewheel") == 0);
    assert(std::strcmp(label_for(20, 1, false), "MED") == 0 && std::strcmp(label_for(20, 1, true), "Medic") == 0);
    assert(std::strcmp(label_for(20, 2, false), "SAG") == 0 && std::strcmp(label_for(20, 2, true), "Sage") == 0);
    assert(std::strcmp(label_for(22, 1, false), "INQ") == 0 && std::strcmp(label_for(22, 1, true), "Inquisitor") == 0);
    assert(std::strcmp(label_for(22, 2, false), "SPB") == 0 && std::strcmp(label_for(22, 2, true), "Spellblade") == 0);
    assert(std::strcmp(label_for(22, 3, false), "LFB") == 0 && std::strcmp(label_for(22, 3, true), "Lifebinder") == 0);
    assert(label_for(3, 1, false) == nullptr);

    original_lookup = &fake_lookup;
    original_sprite = reinterpret_cast<uintptr_t>(&fake_sprite);
    native_text = &fake_text;
    selftest_alive = true;

    // Test Search rows for MNK Sensei, BLM Necromancer, DNC Bladewheel, SCH Sage, RUN Spellblade.
    state = {};
    make_row(row_a, 301, marker | 1, 2); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 2), "Sensei") == 0);
    make_row(row_a, 302, marker | 1, 4); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 4), "Necromancer") == 0);
    make_row(row_a, 303, marker | 1, 19); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 19), "Bladewheel") == 0);
    make_row(row_a, 304, marker | 2, 20); state.decoded(row_a);
    assert(state.row_branch(row_a) == 2 && std::strcmp(full_abi(row_a, 20), "Sage") == 0);
    make_row(row_a, 305, marker | 2, 22); state.decoded(row_a);
    assert(state.row_branch(row_a) == 2 && std::strcmp(full_abi(row_a, 22), "Spellblade") == 0);

    // Test item_label for RUN Lifebinder.
    uint8_t run_event[8] = {1, 1, 22, 3, 100, 0, 0, 0};
    state.update(run_event, 8, GetTickCount());
    assert(std::strcmp(item_label(2, 22), "LFB") == 0);
    assert(std::strcmp(item_label(2, 1), "WAR") == 0);
    selftest_alive = false;
}

int main() {
    uint8_t event[8] = {1, 1, 1, 2, 100, 0, 0, 0};
    state.update(event, 8, 0xffffff00);
    assert(state.alive(0xffffff10, 100, 1));
    assert(state.alive(0x500, 100, 1));
    assert(!state.alive(0x1000, 100, 1));
    assert(!state.alive(0xffffff10, 101, 1));
    assert(!state.alive(0xffffff10, 100, 2));
    make_row(row_a, 101, marker | 1); state.decoded(row_a);
    make_row(row_b, 102, marker | 3); state.decoded(row_b);
    assert(u32(row_a + 20) == 0 && state.row_branch(row_a) == 1 && state.row_branch(row_b) == 3);
    make_row(row_b, 102, 0); state.decoded(row_b);
    assert(state.row_branch(row_b) == 0 && state.row_branch(row_a) == 1);
    make_row(row_b, 102, marker | 2, 2); state.decoded(row_b); assert(state.row_branch(row_b) == 0);
    make_row(row_b, 102, marker | 2, 1, 0x4000); state.decoded(row_b); assert(state.row_branch(row_b) == 0);
    make_row(row_b, 102, marker | 4); state.decoded(row_b); assert(state.row_branch(row_b) == 0 && u32(row_b + 20) == 0);
    make_row(row_b, 102, 0x12345678); state.decoded(row_b); assert(u32(row_b + 20) == 0x12345678);
    original_lookup = &fake_lookup;
    original_sprite = reinterpret_cast<uintptr_t>(&fake_sprite);
    native_text = &fake_text;
    selftest_alive = true;
    assert(sprite_abi(reinterpret_cast<void*>(&normal_sprite_hook), row_a));
    assert(sprite_abi(reinterpret_cast<void*>(&master_sprite_hook), row_a));
    assert(text_calls == 2 && sprite_calls == 0 && std::strcmp(last_text, "CDR") == 0);
    assert(std::strcmp(full_abi(row_a, 1), "Commander") == 0);
    assert(std::strcmp(full_abi(row_a, 2), "Monk") == 0);
    selftest_alive = false;
    assert(sprite_abi(reinterpret_cast<void*>(&normal_sprite_hook), row_a));
    assert(sprite_abi(reinterpret_cast<void*>(&master_sprite_hook), row_a));
    assert(sprite_calls == 2);
    assert(std::strcmp(full_abi(row_a, 1), "Warrior") == 0);
    event[0] = 2; state.update(event, 8, 0); assert(state.character == 0 && state.row_branch(row_a) == 0);
    assert(!supported(nullptr));
    auto* memory = static_cast<uint8_t*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    assert(memory != nullptr);
    const uint8_t original[5] = {0xe8, 1, 2, 3, 4}; std::memcpy(memory, original, 5);
    Patch patch{0, reinterpret_cast<void*>(&normal_sprite_hook)};
    assert(patch.install(memory) && std::memcmp(memory, original, 5) != 0);
    assert(memory[0] == 0xe8 && memory[5] == 0);
    assert(patch.restore() && std::memcmp(memory, original, 5) == 0);
    assert(patch.install(memory)); memory[1] ^= 1;
    assert(!patch.restore());
    memory[58] = 0xaa; memory[64] = 0xbb;
    std::memcpy(memory + 59, original, 5);
    Patch boundary{59, reinterpret_cast<void*>(&normal_sprite_hook)};
    assert(boundary.install(memory) && memory[58] == 0xaa && memory[59] == 0xe8 && memory[64] == 0xbb);
    assert(boundary.restore() && std::memcmp(memory + 59, original, 5) == 0);
    std::memcpy(memory + 62, original, 5);
    Patch crossing{62, reinterpret_cast<void*>(&normal_sprite_hook)};
    assert(!crossing.install(memory) && std::memcmp(memory + 62, original, 5) == 0);
    uint8_t wrong[5]; std::memcpy(wrong, original, 5); wrong[1] ^= 0x40;
    assert(!Patch::write(memory + 62, wrong, original));
    std::memcpy(memory, original, 5);
    assert(!Patch::write(memory, wrong, original) && std::memcmp(memory, original, 5) == 0);
    uint8_t expected[24]; std::memset(expected, 0x55, 24);
    std::memcpy(memory, expected, 24); memory[0] = 0xe9;
    const uint32_t target = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&fake_text) - reinterpret_cast<uintptr_t>(memory + 5));
    std::memcpy(memory + 1, &target, 4); std::memset(memory + 5, 0x90, 5);
    assert(host_detour(memory, expected, 24, 10, GetModuleHandleW(nullptr)));
    assert(!host_detour(memory, expected, 24, 10, nullptr));
    memory[10] ^= 1; assert(!host_detour(memory, expected, 24, 10, GetModuleHandleW(nullptr)));
    VirtualFree(memory, 0, MEM_RELEASE);
    transport_checks();
    multi_job_checks();
    enabled.store(false); state = {};
    original_decode = &fake_search_decode;
    make_row(row_b, 200, marker | 3);
    assert(decode_row(nullptr, row_b, 1) == row_b + 72 && u32(row_b + 20) == 0 && state.row_branch(row_b) == 0);
    make_row(row_b, 200, 0x12345678);
    decode_row(nullptr, row_b, 1); assert(u32(row_b + 20) == 0x12345678);
    const HMODULE dll = LoadLibraryA("crystaljobs.dll");
    assert(dll != nullptr);
    const auto initialize = reinterpret_cast<uint32_t(__stdcall*)()>(GetProcAddress(dll, "CrystalJobsInitialize"));
    const auto shutdown = reinterpret_cast<uint32_t(__stdcall*)()>(GetProcAddress(dll, "CrystalJobsShutdown"));
    const auto status = reinterpret_cast<uint32_t(__stdcall*)(CrystalJobsStatus*, uint32_t)>(GetProcAddress(dll, "CrystalJobsGetStatus"));
    assert(initialize != nullptr && shutdown != nullptr && status != nullptr && GetProcAddress(dll, "CrystalJobsSetState") != nullptr);
    CrystalJobsStatus snapshot{};
    assert(status(&snapshot, sizeof(snapshot)) == 0 && snapshot.version == 1 && snapshot.hooks == 0);
    assert(initialize() == 1 && status(&snapshot, sizeof(snapshot)) == 0 && snapshot.hooks == 0 && snapshot.last_error == 1);
    assert(shutdown() == 0);
    FreeLibrary(dll);
    std::puts("PASS: all 6 OverlordsXI soul jobs (WAR/MNK/BLM/DNC/SCH/RUN), mixed rows/privacy/revoke/lease, x86 adapter ABI, patch restore/conflict, native codec preservation/correlation/bounds, timeout/nonce exhaustion, late-reply sink.");
}
