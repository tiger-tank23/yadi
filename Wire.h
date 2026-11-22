#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

static inline void put32(uint8_t *p, uint32_t n) {
    p[0] = n >> 24; p[1] = n >> 16; p[2] = n >> 8; p[3] = n;
}
// Caller supplies room for 15 + count bytes. The body is already at out + 12.
static inline size_t seal(uint8_t *out, uint8_t command, size_t count) {
    memcpy(out, "YD<", 3);
    put32(out + 3, (uint32_t)count + 8);
    out[7] = command;
    put32(out + 8, (uint32_t)count);
    uint8_t sum = 0;
    for (size_t i = 0; i < count; i++) sum += out[12 + i];
    out[12 + count] = sum;
    memcpy(out + 13 + count, "KJ", 2);
    return count + 15;
}
static inline uint16_t imageCRC(const uint8_t *p, size_t n) {
    uint16_t crc = 0xffff;
    while (n--) {
        crc ^= *p++;
        for (unsigned bit = 0; bit < 8; bit++)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xa001 : 0);
    }
    return crc;
}
static inline size_t fragmentPacket(uint8_t *out, const uint8_t *jpeg, uint32_t size,
                                    uint32_t offset, uint32_t frame, uint16_t crc, uint32_t ms) {
    uint32_t count = size - offset;
    if (count > 1434) count = 1434;
    uint8_t *p = out + 12;
    p[0] = crc; p[1] = crc >> 8;
    p[2] = count >> 8; p[3] = count;
    put32(p + 4, frame); put32(p + 8, size); put32(p + 12, offset); put32(p + 16, ms);
    memcpy(p + 20, jpeg + offset, count);
    return seal(out, 0x12, 20 + count);
}
