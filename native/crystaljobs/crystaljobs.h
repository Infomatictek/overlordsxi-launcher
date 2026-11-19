#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define CRYSTALJOBS_CALL __stdcall
#else
#define CRYSTALJOBS_CALL
#endif
#ifdef __cplusplus
extern "C" {
#endif

typedef struct CrystalJobsStatus {
    uint32_t size, version, enabled, hooks, character_id, job, known, branch;
    uint32_t search_rows, decoded_rows, item_labels, search_labels, full_labels;
    uint32_t queries_sent, replies_accepted, replies_rejected, last_error;
} CrystalJobsStatus;

/* Call outside DllMain, after FFXiMain has unpacked and before character login.
   0=success; 1=unsupported client/layout; 2=initialization failure; 3=restore conflict. */
uint32_t CRYSTALJOBS_CALL CrystalJobsInitialize(void);
uint32_t CRYSTALJOBS_CALL CrystalJobsShutdown(void);
uint32_t CRYSTALJOBS_CALL CrystalJobsGetStatus(CrystalJobsStatus* status, uint32_t size);
/* Optional existing-addon bridge; never required for standalone operation. */
uint32_t CRYSTALJOBS_CALL CrystalJobsSetState(const uint8_t* bytes, uint32_t size);

/* Generic native Soul Action catalog API (version 1). */
enum {
    CRYSTALJOBS_ACTION_SPELL       = 1,
    CRYSTALJOBS_ACTION_ABILITY     = 2,
    CRYSTALJOBS_ACTION_WEAPONSKILL = 3
};

enum {
    CRYSTALJOBS_CAP_EQUIPMENT_SOUL_NAME = 1u << 0,
    CRYSTALJOBS_CAP_SEARCH_SOUL_LABELS  = 1u << 1,
    CRYSTALJOBS_CAP_MAGIC_MENU_NAMES    = 1u << 2,
    CRYSTALJOBS_CAP_MAGIC_MENU_DESC     = 1u << 3,
    CRYSTALJOBS_CAP_MAGIC_TARGET_HEADER = 1u << 4,
    CRYSTALJOBS_CAP_MAGIC_MENU_ICONS    = 1u << 5,
    CRYSTALJOBS_CAP_ABILITY_MENU_NAMES  = 1u << 6,
    CRYSTALJOBS_CAP_ABILITY_MENU_DESC   = 1u << 7,
    CRYSTALJOBS_CAP_ABILITY_TARGET_HDR  = 1u << 8,
    CRYSTALJOBS_CAP_ABILITY_MENU_ICONS  = 1u << 9
};

typedef struct CrystalJobsActionEntry {
    uint32_t size;
    uint8_t  job;
    uint8_t  branch;
    uint16_t action_id;
    uint32_t kind;
    uint16_t icon_id;
    uint16_t icon_id_v2;
    char     name[80];
    char     description[192];
} CrystalJobsActionEntry;

typedef struct CrystalJobsActionStatus {
    uint32_t size;
    uint32_t version;
    uint32_t capabilities;
    uint32_t catalog_count;
    uint32_t catalog_generation;
    uint32_t active_job;
    uint32_t active_branch;
    uint32_t active_source;
    uint32_t magic_name_hits;
    uint32_t magic_desc_hits;
    uint32_t magic_icon_hits;
    uint32_t ability_name_hits;
    uint32_t ability_desc_hits;
    uint32_t ability_icon_hits;
    uint32_t total_hooks;
    uint32_t expected_hooks;
} CrystalJobsActionStatus;

uint32_t CRYSTALJOBS_CALL CrystalJobsReplaceCatalog(const CrystalJobsActionEntry* entries, uint32_t count);
uint32_t CRYSTALJOBS_CALL CrystalJobsUpsertAction(const CrystalJobsActionEntry* entry);
uint32_t CRYSTALJOBS_CALL CrystalJobsClearCatalog(void);
uint32_t CRYSTALJOBS_CALL CrystalJobsSetActiveSoul(uint32_t job, uint32_t branch, uint32_t character_id);
uint32_t CRYSTALJOBS_CALL CrystalJobsClearActiveSoul(void);
uint32_t CRYSTALJOBS_CALL CrystalJobsGetActionStatus(CrystalJobsActionStatus* status, uint32_t size);

#ifdef __cplusplus
}
#endif
