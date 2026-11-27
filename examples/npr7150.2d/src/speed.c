// Speed governor: the speed the motors are commanded to.
// implements: DES-002
#include "rover.h"

#define MAX_SPEED_MM_S 500

int16_t speed_command(const struct command *c, bool lost) {
  if (lost) return 0;
  if (c->speed_mm_s > MAX_SPEED_MM_S) return MAX_SPEED_MM_S;
  if (c->speed_mm_s < -MAX_SPEED_MM_S) return -MAX_SPEED_MM_S;
  return c->speed_mm_s;
}
