#include <assert.h>
#include "../src/rover.h"

// verifies: SRS-001
void test_link_lost_after_two_seconds(void) {
  uint8_t frame[6] = {44, 1, 0, 0};
  uint16_t crc = crc16(frame, 4);
  frame[4] = (uint8_t)crc;
  frame[5] = (uint8_t)(crc >> 8);
  struct command c;
  assert(link_decode(frame, 1000, &c));
  assert(!link_lost(2999));
  assert(link_lost(3000));
  assert(speed_command(&c, link_lost(3000)) == 0);
}

// verifies: SRS-003
void test_decodes_speed_and_heading(void) {
  uint8_t frame[6] = {44, 1, 16, 14};
  uint16_t crc = crc16(frame, 4);
  frame[4] = (uint8_t)crc;
  frame[5] = (uint8_t)(crc >> 8);
  struct command c;
  assert(link_decode(frame, 0, &c));
  assert(c.speed_mm_s == 300 && c.heading_ddeg == 3600);
}
