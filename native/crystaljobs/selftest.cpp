#define CRYSTALJOBS_SELFTEST
#include "crystaljobs.cpp"
#include <cassert>

static uint8_t row_a[72]{}, row_b[72]{};
static uint32_t sprite_calls, simple_sprite_calls, text_calls, persona_text_calls, last_persona_color;
static const char* last_text;
static const char* last_persona_text;
static int __cdecl fake_text(int x, int y, const char* text, uint32_t color, float sx, float sy, int center) {
    assert(x == 100 && y == 50 && color == 0x80808080 && sx == 0.75f && sy == 0.75f && center == 0);
    ++text_calls; last_text = text; return x;
}
static int __cdecl fake_persona_text(int x, int y, const char* text, uint32_t color, float sx, float sy, int center) {
    assert(x == 142 && y == 69 && sx == 1.0f && sy == 1.0f && center == 0);
    ++persona_text_calls; last_persona_text = text; last_persona_color = color; return x;
}
static int __fastcall fake_sprite(void*, void*, int x, int y, float sx, float sy, uint32_t color, int center, int first, int count) {
    assert(x == 100 && y == 50 && sx == 1.0f && sy == 1.0f && color == 0x80808080 && center == 0 && first == 0 && count == 0);
    ++sprite_calls; return 1;
}
static void __fastcall fake_sprite_simple(void* self, void*, int x, int y, uint32_t color, int center, int first) {
    assert(reinterpret_cast<uintptr_t>(self) == 0x34567890u && x == 142 && y == 69 && (color == 0x80808080u || color == 0x802060a0u) && center == 0 && first == 0);
    ++simple_sprite_calls;
}
static uint32_t fake_spell_name_calls, fake_spell_desc_calls, fake_abil_name_calls, fake_abil_desc_calls, fake_icon_calls;
static uint32_t last_icon_v1, last_icon_v2;
static const char* __fastcall fake_spell_name_fn(void* self, void*, int id) {
    assert(reinterpret_cast<uintptr_t>(self) == 0x2468ace0u);
    ++fake_spell_name_calls;
    if (id == 338) return "Utsusemi: Ichi";
    if (id == 339) return "Utsusemi: Ni";
    return "Vanilla Spell";
}
static const char* __fastcall fake_spell_desc_fn(void* self, void*, int id) {
    assert(reinterpret_cast<uintptr_t>(self) == 0x2468ace0u);
    ++fake_spell_desc_calls;
    return id == 338 ? "Vanilla Utsusemi Ichi desc." : "Vanilla Spell desc.";
}
static const char* __fastcall fake_abil_name_fn(void* self, void*, int id) {
    assert(reinterpret_cast<uintptr_t>(self) == 0x2468ace0u);
    ++fake_abil_name_calls;
    if (id == 128) return "Blade: Jin";
    if (id == 600) return "Yonin";
    return "Vanilla Ability";
}
static const char* __fastcall fake_abil_desc_fn(void* self, void*, int id) {
    assert(reinterpret_cast<uintptr_t>(self) == 0x2468ace0u);
    ++fake_abil_desc_calls;
    return id == 128 ? "Vanilla WS desc." : "Vanilla JA desc.";
}
static void* __cdecl fake_action_icon_fn(uint32_t v1, uint32_t v2) {
    ++fake_icon_calls;
    last_icon_v1 = v1;
    last_icon_v2 = v2;
    return reinterpret_cast<void*>(0x13579bdfu);
}
static const char* __cdecl fake_lookup(int table, int job) {
    assert(table == 18 || table == 2);
    if (table == 2) {
        switch (job) {
            case 1: return "WAR";
            case 2: return "MNK";
            case 4: return "BLM";
            case 12: return "SAM";
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

static __declspec(naked) bool persona_abi(void*, uint32_t) {
    __asm {
        push ebp
        push ebx
        push esi
        push edi
        mov ebx, 12345678h
        mov esi, 23456789h
        mov edi, 3456789ah
        mov ebp, 456789abh
        mov eax, [esp + 24]
        push 56789abch
        push 0
        push 0
        push eax
        push 69
        push 142
        mov ecx, 34567890h
        call dword ptr [esp + 44]
        xor eax, eax
        cmp dword ptr [esp], 56789abch
        jne failed
        cmp ebx, 12345678h
        jne failed
        cmp esi, 23456789h
        jne failed
        cmp edi, 3456789ah
        jne failed
        cmp ebp, 456789abh
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

static __declspec(naked) const char* action_str_abi(void*, int32_t) {
    __asm {
        push ebp
        push ebx
        push esi
        push edi
        mov ebx, 11223344h
        mov esi, 22334455h
        mov edi, 33445566h
        mov ebp, 44556677h
        mov eax, [esp + 24]
        push 55667788h
        push eax
        mov ecx, 2468ace0h
        call dword ptr [esp + 28]
        cmp dword ptr [esp], 55667788h
        jne failed
        cmp ebx, 11223344h
        jne failed
        cmp esi, 22334455h
        jne failed
        cmp edi, 33445566h
        jne failed
        cmp ebp, 44556677h
        jne failed
        jmp done
    failed:
        xor eax, eax
    done:
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
    // Job 23 (MON) has no soul crystals, so prepare() does not poll.
    uint8_t job[16]; make_packet(job, 0x061, 16); job[12] = 23;
    model.incoming(job, 16, 2300, labels); assert(model.job == 23 && !labels.known);
    assert(!model.prepare(request, counter, 2400));
    // Job 22 (RUN) has soul crystals (Spellblade/Lifebinder/Inquisitor), so prepare() polls with job=22.
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
    // Check all 22 OverlordsXI jobs (66 soul specs).
    assert(std::strcmp(label_for(1, 1, false), "CDR") == 0 && std::strcmp(label_for(1, 1, true), "Commander") == 0);
    assert(std::strcmp(label_for(1, 2, false), "BRZ") == 0 && std::strcmp(label_for(1, 2, true), "Berserker") == 0);
    assert(std::strcmp(label_for(1, 3, false), "SPT") == 0 && std::strcmp(label_for(1, 3, true), "Spartan") == 0);
    assert(std::strcmp(label_for(2, 1, false), "SEN") == 0 && std::strcmp(label_for(2, 1, true), "Sensei") == 0);
    assert(std::strcmp(label_for(2, 2, false), "CWV") == 0 && std::strcmp(label_for(2, 2, true), "Chi Weaver") == 0);
    assert(std::strcmp(label_for(2, 3, false), "BLK") == 0 && std::strcmp(label_for(2, 3, true), "Black Belt") == 0);
    assert(std::strcmp(label_for(3, 1, false), "BSH") == 0 && std::strcmp(label_for(3, 1, true), "Bishop") == 0);
    assert(std::strcmp(label_for(3, 2, false), "ZEL") == 0 && std::strcmp(label_for(3, 2, true), "Zealot") == 0);
    assert(std::strcmp(label_for(3, 3, false), "VLK") == 0 && std::strcmp(label_for(3, 3, true), "Valkyrie") == 0);
    assert(std::strcmp(label_for(4, 1, false), "AST") == 0 && std::strcmp(label_for(4, 1, true), "Astromancer") == 0);
    assert(std::strcmp(label_for(4, 2, false), "CHN") == 0 && std::strcmp(label_for(4, 2, true), "Channeler") == 0);
    assert(std::strcmp(label_for(4, 3, false), "NEC") == 0 && std::strcmp(label_for(4, 3, true), "Necromancer") == 0);
    assert(std::strcmp(label_for(5, 1, false), "DLS") == 0 && std::strcmp(label_for(5, 1, true), "Crimson Duelist") == 0);
    assert(std::strcmp(label_for(5, 2, false), "RYT") == 0 && std::strcmp(label_for(5, 2, true), "Royal Tactician") == 0);
    assert(std::strcmp(label_for(5, 3, false), "SCW") == 0 && std::strcmp(label_for(5, 3, true), "Scarlet Weaver") == 0);
    assert(std::strcmp(label_for(6, 1, false), "TRK") == 0 && std::strcmp(label_for(6, 1, true), "Trickster") == 0);
    assert(std::strcmp(label_for(6, 2, false), "BND") == 0 && std::strcmp(label_for(6, 2, true), "Bandit") == 0);
    assert(std::strcmp(label_for(6, 3, false), "PHN") == 0 && std::strcmp(label_for(6, 3, true), "Phantom") == 0);
    assert(std::strcmp(label_for(7, 1, false), "TMP") == 0 && std::strcmp(label_for(7, 1, true), "Templar") == 0);
    assert(std::strcmp(label_for(7, 2, false), "DFN") == 0 && std::strcmp(label_for(7, 2, true), "Defender") == 0);
    assert(std::strcmp(label_for(7, 3, false), "OTB") == 0 && std::strcmp(label_for(7, 3, true), "Oathbreaker") == 0);
    assert(std::strcmp(label_for(8, 1, false), "RPR") == 0 && std::strcmp(label_for(8, 1, true), "Reaper") == 0);
    assert(std::strcmp(label_for(8, 2, false), "DRN") == 0 && std::strcmp(label_for(8, 2, true), "Dreadnought") == 0);
    assert(std::strcmp(label_for(8, 3, false), "SCR") == 0 && std::strcmp(label_for(8, 3, true), "Scourge") == 0);
    assert(std::strcmp(label_for(9, 1, false), "UNT") == 0 && std::strcmp(label_for(9, 1, true), "Untamed") == 0);
    assert(std::strcmp(label_for(9, 2, false), "SLB") == 0 && std::strcmp(label_for(9, 2, true), "Soulbeast") == 0);
    assert(std::strcmp(label_for(9, 3, false), "BSP") == 0 && std::strcmp(label_for(9, 3, true), "Beastspeaker") == 0);
    assert(std::strcmp(label_for(10, 1, false), "ADV") == 0 && std::strcmp(label_for(10, 1, true), "Adventurer") == 0);
    assert(std::strcmp(label_for(10, 2, false), "MUS") == 0 && std::strcmp(label_for(10, 2, true), "Musician") == 0);
    assert(std::strcmp(label_for(10, 3, false), "MIN") == 0 && std::strcmp(label_for(10, 3, true), "Minstrel") == 0);
    assert(std::strcmp(label_for(11, 1, false), "SNP") == 0 && std::strcmp(label_for(11, 1, true), "Sniper") == 0);
    assert(std::strcmp(label_for(11, 2, false), "HNT") == 0 && std::strcmp(label_for(11, 2, true), "Huntsman") == 0);
    assert(std::strcmp(label_for(11, 3, false), "ACA") == 0 && std::strcmp(label_for(11, 3, true), "Arcane Archer") == 0);
    assert(std::strcmp(label_for(12, 1, false), "RON") == 0 && std::strcmp(label_for(12, 1, true), "Ronin") == 0);
    assert(std::strcmp(label_for(12, 2, false), "IMP") == 0 && std::strcmp(label_for(12, 2, true), "Imperial Archer") == 0);
    assert(std::strcmp(label_for(12, 3, false), "WRL") == 0 && std::strcmp(label_for(12, 3, true), "Warlord") == 0);
    assert(std::strcmp(label_for(13, 1, false), "KRG") == 0 && std::strcmp(label_for(13, 1, true), "Shinobi") == 0);
    assert(std::strcmp(label_for(13, 2, false), "KGM") == 0 && std::strcmp(label_for(13, 2, true), "Kagemusha") == 0);
    assert(std::strcmp(label_for(13, 3, false), "NGB") == 0 && std::strcmp(label_for(13, 3, true), "Nightblade") == 0);
    assert(std::strcmp(label_for(14, 1, false), "LNC") == 0 && std::strcmp(label_for(14, 1, true), "Lancer") == 0);
    assert(std::strcmp(label_for(14, 2, false), "SKY") == 0 && std::strcmp(label_for(14, 2, true), "Skyborn") == 0);
    assert(std::strcmp(label_for(14, 3, false), "WYV") == 0 && std::strcmp(label_for(14, 3, true), "Wyvernheart") == 0);
    assert(std::strcmp(label_for(15, 1, false), "PRM") == 0 && std::strcmp(label_for(15, 1, true), "Primalist") == 0);
    assert(std::strcmp(label_for(15, 2, false), "CEL") == 0 && std::strcmp(label_for(15, 2, true), "Celestial") == 0);
    assert(std::strcmp(label_for(15, 3, false), "HLD") == 0 && std::strcmp(label_for(15, 3, true), "Herald") == 0);
    assert(std::strcmp(label_for(16, 1, false), "WMG") == 0 && std::strcmp(label_for(16, 1, true), "Warmage") == 0);
    assert(std::strcmp(label_for(16, 2, false), "MAG") == 0 && std::strcmp(label_for(16, 2, true), "Magus") == 0);
    assert(std::strcmp(label_for(16, 3, false), "AZB") == 0 && std::strcmp(label_for(16, 3, true), "Azure Bastion") == 0);
    assert(std::strcmp(label_for(17, 1, false), "FLT") == 0 && std::strcmp(label_for(17, 1, true), "Flintlock") == 0);
    assert(std::strcmp(label_for(17, 2, false), "GMB") == 0 && std::strcmp(label_for(17, 2, true), "Gambler") == 0);
    assert(std::strcmp(label_for(17, 3, false), "BUC") == 0 && std::strcmp(label_for(17, 3, true), "Buccaneer") == 0);
    assert(std::strcmp(label_for(18, 1, false), "VNG") == 0 && std::strcmp(label_for(18, 1, true), "Vanguard") == 0);
    assert(std::strcmp(label_for(18, 2, false), "PGL") == 0 && std::strcmp(label_for(18, 2, true), "Pugilist") == 0);
    assert(std::strcmp(label_for(18, 3, false), "ANM") == 0 && std::strcmp(label_for(18, 3, true), "Animist") == 0);
    assert(std::strcmp(label_for(19, 1, false), "MRS") == 0 && std::strcmp(label_for(19, 1, true), "Mirage Sentinel") == 0);
    assert(std::strcmp(label_for(19, 2, false), "VMP") == 0 && std::strcmp(label_for(19, 2, true), "Vampire") == 0);
    assert(std::strcmp(label_for(19, 3, false), "BLW") == 0 && std::strcmp(label_for(19, 3, true), "Bladewheel") == 0);
    assert(std::strcmp(label_for(20, 1, false), "MDC") == 0 && std::strcmp(label_for(20, 1, true), "Medic") == 0);
    assert(std::strcmp(label_for(20, 2, false), "SAG") == 0 && std::strcmp(label_for(20, 2, true), "Sage") == 0);
    assert(std::strcmp(label_for(20, 3, false), "ARC") == 0 && std::strcmp(label_for(20, 3, true), "Archivist") == 0);
    assert(std::strcmp(label_for(21, 1, false), "DIV") == 0 && std::strcmp(label_for(21, 1, true), "Diviner") == 0);
    assert(std::strcmp(label_for(21, 2, false), "VRD") == 0 && std::strcmp(label_for(21, 2, true), "Verdant") == 0);
    assert(std::strcmp(label_for(21, 3, false), "TRM") == 0 && std::strcmp(label_for(21, 3, true), "Terramancer") == 0);
    assert(std::strcmp(label_for(22, 1, false), "SPB") == 0 && std::strcmp(label_for(22, 1, true), "Spellblade") == 0);
    assert(std::strcmp(label_for(22, 2, false), "LFB") == 0 && std::strcmp(label_for(22, 2, true), "Lifebinder") == 0);
    assert(std::strcmp(label_for(22, 3, false), "INQ") == 0 && std::strcmp(label_for(22, 3, true), "Inquisitor") == 0);
    assert(label_for(23, 1, false) == nullptr);

    original_lookup = &fake_lookup;
    original_sprite = reinterpret_cast<uintptr_t>(&fake_sprite);
    native_text = &fake_text;
    selftest_alive = true;

    // Test Search rows for MNK, BLM, SAM, DNC, SCH, RUN.
    state = {};
    make_row(row_a, 301, marker | 1, 2); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 2), "Sensei") == 0);
    make_row(row_a, 306, marker | 2, 2); state.decoded(row_a);
    assert(state.row_branch(row_a) == 2 && std::strcmp(full_abi(row_a, 2), "Chi Weaver") == 0);
    make_row(row_a, 307, marker | 3, 2); state.decoded(row_a);
    assert(state.row_branch(row_a) == 3 && std::strcmp(full_abi(row_a, 2), "Black Belt") == 0);
    make_row(row_a, 302, marker | 3, 4); state.decoded(row_a);
    assert(state.row_branch(row_a) == 3 && std::strcmp(full_abi(row_a, 4), "Necromancer") == 0);
    make_row(row_a, 308, marker | 1, 12); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 12), "Ronin") == 0);
    make_row(row_a, 309, marker | 2, 12); state.decoded(row_a);
    assert(state.row_branch(row_a) == 2 && std::strcmp(full_abi(row_a, 12), "Imperial Archer") == 0);
    make_row(row_a, 310, marker | 3, 12); state.decoded(row_a);
    assert(state.row_branch(row_a) == 3 && std::strcmp(full_abi(row_a, 12), "Warlord") == 0);
    make_row(row_a, 303, marker | 3, 19); state.decoded(row_a);
    assert(state.row_branch(row_a) == 3 && std::strcmp(full_abi(row_a, 19), "Bladewheel") == 0);
    make_row(row_a, 304, marker | 2, 20); state.decoded(row_a);
    assert(state.row_branch(row_a) == 2 && std::strcmp(full_abi(row_a, 20), "Sage") == 0);
    make_row(row_a, 305, marker | 1, 22); state.decoded(row_a);
    assert(state.row_branch(row_a) == 1 && std::strcmp(full_abi(row_a, 22), "Spellblade") == 0);

    // Test item_label for RUN Lifebinder and SAM Imperial Archer.
    uint8_t run_event[8] = {1, 1, 22, 2, 100, 0, 0, 0};
    state.update(run_event, 8, GetTickCount());
    assert(std::strcmp(item_label(2, 22), "LFB") == 0);
    assert(std::strcmp(item_label(2, 1), "WAR") == 0);
    uint8_t sam_event[8] = {1, 1, 12, 2, 100, 0, 0, 0};
    state.update(sam_event, 8, GetTickCount());
    assert(std::strcmp(item_label(2, 12), "IMP") == 0);

    // Test menu2fon 3-glyph sprite rendering (24px wide: x0 = 0, 8, 16) and tile restoration.
    uint8_t mock_tile[0xE0]{}, mock_node[0x20]{}, mock_sprite[0x30]{};
    const int16_t war_corners[8] = {0, -1, 24, -1, 0, 9, 24, 9};
    const float war_uv[2] = {0.0f, 184.0f / 256.0f};
    std::memcpy(mock_tile + 0xC0, war_corners, sizeof(war_corners));
    std::memcpy(mock_tile + 0x64, war_uv, sizeof(war_uv));
    uint8_t* tile_ptr = mock_tile;
    std::memcpy(mock_node + 0x10, &tile_ptr, sizeof(tile_ptr));
    uint8_t* node_ptr = mock_node;
    std::memcpy(mock_sprite + 0x04, &node_ptr, sizeof(node_ptr));
    const uint32_t one_tile = 1;
    std::memcpy(mock_sprite + 0x14, &one_tile, sizeof(one_tile));
    uint8_t* sprite_entries[2] = {nullptr, mock_sprite};
    uint8_t** sprite_table = sprite_entries;
    void* sheet_obj = &sprite_table;
    pname_sheet_slot = &sheet_obj;

    sprite_calls = 0; text_calls = 0;
    make_row(row_a, 320, marker | 2, 1); state.decoded(row_a); // WAR branch 2 = BRZ
    assert(sprite_abi(reinterpret_cast<void*>(&normal_sprite_hook), row_a));
    assert(sprite_calls == 3 && text_calls == 0);
    assert(std::memcmp(mock_tile + 0xC0, war_corners, sizeof(war_corners)) == 0);
    assert(std::memcmp(mock_tile + 0x64, war_uv, sizeof(war_uv)) == 0);
    pname_sheet_slot = nullptr;

    selftest_alive = false;
}

static void equipment_persona_checks() {
    original_sprite_simple = reinterpret_cast<uintptr_t>(&fake_sprite_simple);
    native_text = &fake_persona_text;
    uint8_t mock_main_job = 13; // NIN
    main_job_slot = &mock_main_job;
    selftest_alive = true;
    simple_sprite_calls = 0;
    persona_text_calls = 0;
    last_persona_text = nullptr;
    last_persona_color = 0;

    // Active NIN (13) Soul branch 1 -> "Shinobi", preserving normal and level-sync colors.
    const uint32_t before_full = full_lookups.load();
    uint8_t ev[8] = {1, 1, 13, 1, 100, 0, 0, 0};
    state.update(ev, 8, GetTickCount());
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 1 && simple_sprite_calls == 0);
    assert(std::strcmp(last_persona_text, "Shinobi") == 0 && last_persona_color == 0x80808080u);
    assert(full_lookups.load() == before_full + 1);

    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x802060a0u));
    assert(persona_text_calls == 2 && simple_sprite_calls == 0);
    assert(std::strcmp(last_persona_text, "Shinobi") == 0 && last_persona_color == 0x802060a0u);

    // Long idle: the short search/session heartbeat lease has expired, but the
    // local persona must keep its last confirmed Soul until explicit revocation.
    state.updated = GetTickCount() - lease_ms - 60000u;
    assert(!state.alive(GetTickCount(), 100, 13));
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 3 && simple_sprite_calls == 0);
    assert(std::strcmp(last_persona_text, "Shinobi") == 0);

    // Live Soul switch without closing the Equipment menu.
    ev[3] = 2; state.update(ev, 8, GetTickCount());
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 4 && std::strcmp(last_persona_text, "Kagemusha") == 0);
    ev[3] = 3; state.update(ev, 8, GetTickCount());
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 5 && std::strcmp(last_persona_text, "Nightblade") == 0);

    // Other jobs (e.g., BLM Astromancer, RDM Crimson Duelist).
    mock_main_job = 4; ev[2] = 4; ev[3] = 1; state.update(ev, 8, GetTickCount());
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 6 && std::strcmp(last_persona_text, "Astromancer") == 0);
    mock_main_job = 5; ev[2] = 5; ev[3] = 1; state.update(ev, 8, GetTickCount());
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 7 && std::strcmp(last_persona_text, "Crimson Duelist") == 0);

    // Fallback to stock sprite on job mismatch, no Soul, explicit revoke, or disabled session.
    mock_main_job = 13; // state.job is still 5
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 7 && simple_sprite_calls == 1);

    ev[2] = 13; ev[3] = 0; state.update(ev, 8, GetTickCount()); // branch 0 = no Soul
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 7 && simple_sprite_calls == 2);

    ev[1] = 0; ev[3] = 1; state.update(ev, 8, GetTickCount()); // unknown
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 7 && simple_sprite_calls == 3);

    ev[1] = 1; ev[3] = 1; state.update(ev, 8, GetTickCount());
    selftest_alive = false; // explicitly disabled / zoning
    assert(persona_abi(reinterpret_cast<void*>(&persona_job_hook), 0x80808080u));
    assert(persona_text_calls == 7 && simple_sprite_calls == 4);

    // Verify 0x14868F signature relocation for relocated FFXiMain.dll (e.g. 0x04860000).
    uint8_t persona_sig[24];
    std::memcpy(persona_sig, signatures[16].bytes, 24);
    assert(signatures[16].rva == 0x14868F);
    relocate_signature(0x14868F, persona_sig, static_cast<uint32_t>(0x04860000u - 0x10000000u));
    assert(u32(persona_sig + 6) == 0x04860000u + 0x4867F2u);
    assert(u32(persona_sig + 17) == 0x04860000u + 0x4867F3u);

    main_job_slot = nullptr;
    native_text = &fake_text;
}

static CrystalJobsActionEntry make_action(uint8_t job, uint8_t branch, uint32_t kind, uint16_t id,
                                          const char* name, const char* desc,
                                          uint16_t icon_v1 = 0xFFFFu, uint16_t icon_v2 = 0xFFFFu) {
    CrystalJobsActionEntry e{};
    e.size = sizeof(e);
    e.job = job;
    e.branch = branch;
    e.kind = kind;
    e.action_id = id;
    e.icon_id = icon_v1;
    e.icon_id_v2 = icon_v2;
    if (name) std::strncpy(e.name, name, sizeof(e.name) - 1);
    if (desc) std::strncpy(e.description, desc, sizeof(e.description) - 1);
    return e;
}

static void action_catalog_checks() {
    original_spell_name = reinterpret_cast<uintptr_t>(&fake_spell_name_fn);
    original_spell_desc = reinterpret_cast<uintptr_t>(&fake_spell_desc_fn);
    original_ability_name_row = reinterpret_cast<uintptr_t>(&fake_abil_name_fn);
    original_ability_name_target = reinterpret_cast<uintptr_t>(&fake_abil_name_fn);
    original_ability_desc = reinterpret_cast<uintptr_t>(&fake_abil_desc_fn);
    original_action_icon = &fake_action_icon_fn;

    fake_spell_name_calls = fake_spell_desc_calls = fake_abil_name_calls = fake_abil_desc_calls = fake_icon_calls = 0;
    uint8_t mock_job = 13;
    main_job_slot = &mock_job;
    selftest_alive = true;

    // Atomic replace with multiple Souls mapping the SAME underlying action IDs differently.
    CrystalJobsActionEntry batch[5] = {
        make_action(13, 1, CRYSTALJOBS_ACTION_SPELL, 338, "Shadow Squadron: Ichi",
                    "Summon 2 offensive shadow clones.", 12, 1024),
        make_action(13, 1, CRYSTALJOBS_ACTION_SPELL, 339, "Shadow Squadron: Ni",
                    "Summon 3 offensive shadow clones."),
        make_action(13, 2, CRYSTALJOBS_ACTION_SPELL, 338, "Mirror Decoy: Ichi",
                    "Kagemusha decoy clone technique."),
        make_action(13, 1, CRYSTALJOBS_ACTION_WEAPONSKILL, 128, "Shadow Rend",
                    "Shinobi shadow-infused weapon skill.", 7, 1007),
        make_action(13, 1, CRYSTALJOBS_ACTION_ABILITY, 600, "Phantom Veil",
                    "Shinobi stealth stance."),
    };
    assert(CrystalJobsReplaceCatalog(batch, 5) == 0);

    // Reject duplicate keys without corrupting existing catalog.
    CrystalJobsActionEntry dup[2] = { batch[0], batch[0] };
    assert(CrystalJobsReplaceCatalog(dup, 2) == 1);
    assert(action_catalog.count() == 5);

    // Row width is adjustable without recompilation; invalid values fail safely.
    assert(CrystalJobsSetActionRowLimit(7) == 1);
    assert(CrystalJobsSetActionRowLimit(49) == 1);
    assert(CrystalJobsSetActionRowLimit(16) == 0);
    char compact[80]{};
    assert(compact_action_row_name("Utsusemi: Ichi", compact, sizeof(compact), 16));
    assert(std::strcmp(compact, "Utsusemi: Ichi") == 0);
    assert(compact_action_row_name("Shadow Squadron: Ichi", compact, sizeof(compact), 16));
    assert(std::strcmp(compact, "Shadow Sq.: Ichi") == 0);
    assert(compact_action_row_name("Extraordinarily Long Action Name", compact, sizeof(compact), 16));
    assert(std::strcmp(compact, "Extraordinar...") == 0);

    // Active NIN (13) branch 1 (Shinobi) via bridge state.
    uint8_t ev[8] = {1, 1, 13, 1, 100, 0, 0, 0};
    state.update(ev, 8, GetTickCount());
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Shadow Sq.: Ichi") == 0);
    assert(magic_icon_hook(99, 200) == reinterpret_cast<void*>(0x13579bdfu) && last_icon_v1 == 12 && last_icon_v2 == 1024);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_desc_hook), 338), "Summon 2 offensive shadow clones.") == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_target_hook), 339), "Shadow Squadron: Ni") == 0);

    // Weapon skill (id < 512) and Job Ability (id >= 512) resolve independently.
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&ability_row_name_hook), 128), "Shadow Rend") == 0);
    assert(ability_icon_hook(5, 50) == reinterpret_cast<void*>(0x13579bdfu) && last_icon_v1 == 7 && last_icon_v2 == 1007);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&ability_desc_hook), 128), "Shinobi shadow-infused weapon skill.") == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&ability_target_hook), 600), "Phantom Veil") == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&ability_desc_hook), 600), "Shinobi stealth stance.") == 0);
    assert(fake_spell_name_calls == 0 && fake_spell_desc_calls == 0 && fake_abil_name_calls == 0 && fake_abil_desc_calls == 0);

    // Switch Soul to Kagemusha (branch 2): same spell ID 338 maps to a different name; 339 falls back to vanilla.
    ev[3] = 2; state.update(ev, 8, GetTickCount());
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Mirror De.: Ichi") == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 339), "Utsusemi: Ni") == 0);
    assert(fake_spell_name_calls == 1);

    // Switch to Nightblade (branch 3, unmapped): falls back to vanilla for 338.
    ev[3] = 3; state.update(ev, 8, GetTickCount());
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Utsusemi: Ichi") == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_desc_hook), 338), "Vanilla Utsusemi Ichi desc.") == 0);

    // Job change mismatch: live job is WAR (1) while state is NIN (13) -> stock fallback!
    ev[3] = 1; state.update(ev, 8, GetTickCount());
    mock_job = 1;
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Utsusemi: Ichi") == 0);
    mock_job = 13;

    // Explicit SetActiveSoul / ClearActiveSoul when bridge state is unknown.
    ev[1] = 0; ev[3] = 0; state.update(ev, 8, GetTickCount());
    assert(CrystalJobsSetActiveSoul(13, 1, 0) == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Shadow Sq.: Ichi") == 0);
    assert(CrystalJobsClearActiveSoul() == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Utsusemi: Ichi") == 0);

    // Full target labels always remain unshortened, even with narrower row budget.
    assert(CrystalJobsSetActionRowLimit(12) == 0);
    assert(CrystalJobsSetActiveSoul(13, 1, 0) == 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_row_name_hook), 338), "Shadow: Ichi") != 0);
    assert(std::strcmp(action_str_abi(reinterpret_cast<void*>(&magic_target_hook), 338), "Shadow Squadron: Ichi") == 0);
    assert(CrystalJobsSetActionRowLimit(16) == 0);
    assert(CrystalJobsClearActiveSoul() == 0);

    // Verify relocations for all new action signatures (base 0x04860000).
    const uint32_t delta = static_cast<uint32_t>(0x04860000u - 0x10000000u);
    for (const auto& sig : signatures) {
        uint8_t buf[24];
        std::memcpy(buf, sig.bytes, 24);
        relocate_signature(sig.rva, buf, delta);
        if (sig.rva == 0x22E245) assert(u32(buf + 7) == 0x04860000u + 0x5793B0u);
        if (sig.rva == 0x22DED1) assert(u32(buf + 7) == 0x04860000u + 0x579638u);
        if (sig.rva == 0x225F5D) {
            assert(u32(buf + 7) == 0x04860000u + 0x5793B0u);
            const uint32_t expected21 = 0x04860000u + 0x6682FCu;
            assert(std::memcmp(buf + 21, &expected21, 3) == 0);
        }
        if (sig.rva == 0x225916) assert(u32(buf + 7) == 0x04860000u + 0x579638u);
        if (sig.rva == 0x22D510) assert(u32(buf + 18) == 0x04860000u + 0x457BD8u);
        if (sig.rva == 0x225120 || sig.rva == 0x2250A0) assert(u32(buf + 2) == 0x04860000u + 0x457BD8u);
    }

    assert(CrystalJobsClearCatalog() == 0 && action_catalog.count() == 0);
    main_job_slot = nullptr;
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
    assert(state.row_branch(row_b) == 3 && state.row_branch(row_a) == 1);
    make_row(row_b, 102, 0, 2); state.decoded(row_b);
    assert(state.row_branch(row_b) == 0 && state.row_branch(row_a) == 1);
    make_row(row_b, 102, marker | 3, 1); state.decoded(row_b);
    assert(state.row_branch(row_b) == 3);
    make_row(row_b, 102, marker | 0, 1); state.decoded(row_b);
    assert(state.row_branch(row_b) == 0 && state.row_branch(row_a) == 1);
    make_row(row_b, 102, marker | 1, 23); state.decoded(row_b); assert(state.row_branch(row_b) == 0);
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
    std::memset(memory + 5, 0xcc, 5); // Microsoft Detours 0xCC padding
    assert(host_detour(memory, expected, 24, 10, GetModuleHandleW(nullptr)));
    assert(!host_detour(memory, expected, 24, 10, nullptr));
    memory[10] ^= 1; assert(!host_detour(memory, expected, 24, 10, GetModuleHandleW(nullptr)));
    VirtualFree(memory, 0, MEM_RELEASE);
    // Verify signature relocation when FFXiMain.dll is relocated (e.g. 0x04860000 under Ashita v4).
    uint8_t reloc_sig[24];
    std::memcpy(reloc_sig, signatures[2].bytes, 24);
    relocate_signature(0x13C302, reloc_sig, static_cast<uint32_t>(0x04860000u - 0x10000000u));
    assert(u32(reloc_sig + 11) == 0x04860000u + 0x370DF8u);
    transport_checks();
    multi_job_checks();
    equipment_persona_checks();
    action_catalog_checks();
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
    const auto get_iface = reinterpret_cast<double(__stdcall*)()>(GetProcAddress(dll, "expGetInterfaceVersion"));
    const auto create_plugin = reinterpret_cast<void*(__stdcall*)(const char*)>(GetProcAddress(dll, "expCreatePlugin"));
    const auto destroy_plugin = reinterpret_cast<void(__stdcall*)(void*)>(GetProcAddress(dll, "expDestroyPlugin"));
    assert(initialize != nullptr && shutdown != nullptr && status != nullptr && GetProcAddress(dll, "CrystalJobsSetState") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsReplaceCatalog") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsUpsertAction") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsSetActionRowLimit") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsClearCatalog") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsSetActiveSoul") != nullptr);
    assert(GetProcAddress(dll, "CrystalJobsClearActiveSoul") != nullptr);
    const auto get_action_st = reinterpret_cast<uint32_t(__stdcall*)(CrystalJobsActionStatus*, uint32_t)>(GetProcAddress(dll, "CrystalJobsGetActionStatus"));
    assert(get_action_st != nullptr);
    CrystalJobsActionStatus act_st{};
    assert(get_action_st(&act_st, sizeof(act_st)) == 0 && act_st.version == 1 && act_st.expected_hooks == 18 && act_st.total_hooks == 0);
    assert(get_iface != nullptr && create_plugin != nullptr && destroy_plugin != nullptr);
    assert(get_iface() == 4.30);
    void* plugin = create_plugin("");
    assert(plugin != nullptr);
    destroy_plugin(plugin);
    CrystalJobsStatus snapshot{};
    assert(status(&snapshot, sizeof(snapshot)) == 0 && snapshot.version == 1 && snapshot.hooks == 0);
    assert(initialize() == 1 && status(&snapshot, sizeof(snapshot)) == 0 && snapshot.hooks == 0 && snapshot.last_error == 1);
    assert(shutdown() == 0);
    FreeLibrary(dll);
    std::puts("PASS: all 7 OverlordsXI soul jobs (WAR/MNK/BLM/SAM/DNC/SCH/RUN), mixed rows/privacy/revoke/lease, x86 adapter ABI, patch restore/conflict, native codec preservation/correlation/bounds, timeout/nonce exhaustion, late-reply sink.");
}
