#include <stdbool.h>
#include <stdint.h>

struct command {
  int16_t speed_mm_s;
  uint16_t heading_ddeg;
};

uint16_t crc16(const uint8_t *data, int len);
void sd_printf(const char *format, ...);

bool link_decode(const uint8_t frame[6], uint32_t now_ms, struct command *out);
bool link_lost(uint32_t now_ms);
int16_t speed_command(const struct command *c, bool lost);
void log_command(const struct command *c, uint32_t now_ms);
