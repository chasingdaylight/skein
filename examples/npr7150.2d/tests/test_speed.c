#include <assert.h>
#include "../src/rover.h"

// verifies: SRS-002
void test_speed_limited(void) {
  struct command fast = {900, 0}, back = {-900, 0}, slow = {200, 0};
  assert(speed_command(&fast, false) == 500);
  assert(speed_command(&back, false) == -500);
  assert(speed_command(&slow, false) == 200);
}
