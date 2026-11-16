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

#ifdef __cplusplus
}
#endif
