// Link monitor: decodes drive commands, and reports the link lost.
// implements: DES-001
#include "rover.h"

#define LINK_TIMEOUT_MS 2000

static uint32_t last_valid_ms;

bool link_decode(const uint8_t frame[6], uint32_t now_ms, struct command *out) {
  if (crc16(frame, 4) != (uint16_t)(frame[4] | frame[5] << 8)) return false;
  out->speed_mm_s = (int16_t)(frame[0] | frame[1] << 8);
  out->heading_ddeg = (uint16_t)(frame[2] | frame[3] << 8);
  last_valid_ms = now_ms;
  return true;
}

bool link_lost(uint32_t now_ms) {
  return now_ms - last_valid_ms >= LINK_TIMEOUT_MS;
}
