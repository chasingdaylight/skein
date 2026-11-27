// Logger: each command, with the controller's clock, on the SD card.
// implements: DES-003
#include "rover.h"

void log_command(const struct command *c, uint32_t now_ms) {
  sd_printf("%lu %d %u\n", (unsigned long)now_ms, c->speed_mm_s, c->heading_ddeg);
}
