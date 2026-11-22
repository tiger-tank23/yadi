#import "CWJPEGInstrument.h"
#import "Wire.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <arpa/inet.h>
#import <poll.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <math.h>
#import <time.h>

static double uptime(void) { return NSProcessInfo.processInfo.systemUptime; }

static int connectSocket(struct sockaddr_in addr, int kind, int port) {
    addr.sin_port = htons(port);
    int fd = socket(AF_INET, kind, 0);
    if (fd < 0) return -1;
    int one = 1;
    struct timeval timeout = {2, 0};
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) < 0 ||
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) < 0 ||
        fcntl(fd, F_SETFL, O_NONBLOCK) < 0) goto failed;
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (errno != EINPROGRESS) goto failed;
        struct pollfd wait = {fd, POLLOUT, 0};
        int status = poll(&wait, 1, 5000);
        if (!status) errno = ETIMEDOUT;
        if (status <= 0) goto failed;
        int err = 0;
        socklen_t len = sizeof(err);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0) goto failed;
        if (err) { errno = err; goto failed; }
    }
    if (fcntl(fd, F_SETFL, 0) == 0) return fd;
failed: {
    int err = errno; close(fd); errno = err; return -1;
}
}

static BOOL control(int fd, uint8_t cmd, const uint8_t body[8]) {
    uint8_t packet[23];
    memcpy(packet + 12, body, 8);
    size_t length = seal(packet, cmd, 8);
    size_t sent = 0;
    while (sent < length) {
        ssize_t n = send(fd, packet + sent, length - sent, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        sent += (size_t)n;
    }
    return YES;
}
static BOOL sendClock(int fd) {
    time_t now = time(NULL);
    struct tm t;
    localtime_r(&now, &t);
    uint8_t body[] = {(uint8_t)(t.tm_year - 100), (uint8_t)(t.tm_mon + 1),
        (uint8_t)t.tm_mday,(uint8_t)t.tm_hour,(uint8_t)t.tm_min,(uint8_t)t.tm_sec,255,255};
    return control(fd, 0x1f, body);
}

@implementation CWJPEGInstrument {
    int _tcp, _udp, _width, _height, _fps;
    uint32_t _frame;


}
- (instancetype)init {
    if ((self = [super init])) {
        _tcp = _udp = -1;

    }
    return self;
}
- (void)stop {
    if (_tcp >= 0) close(_tcp);
    if (_udp >= 0) close(_udp);
    _tcp = _udp = -1;
    _width = _height = 0;
}
- (void)dealloc { [self stop]; }
- (BOOL)fail:(NSString *)reason error:(NSError **)error {
    [self stop];
    if (error) *error = [NSError errorWithDomain:@"CWJPEGInstrument" code:1
        userInfo:@{NSLocalizedDescriptionKey:reason}];
    return NO;
}
- (BOOL)startWithIPv4:(NSString *)address error:(NSError **)error {
    [self stop];
    struct sockaddr_in addr = {.sin_len = sizeof(addr), .sin_family = AF_INET};
    if (inet_pton(AF_INET, address.UTF8String, &addr.sin_addr) != 1)
        return [self fail:@"仪表 IPv4 地址无效" error:error];
    _tcp = connectSocket(addr, SOCK_STREAM, 8888);
    if (_tcp < 0) return [self fail:@"TCP 8888 连接失败" error:error];
    const uint8_t start[] = {5,154,240,255,0,0,5,154};
    if (!sendClock(_tcp) || !control(_tcp, 0x10, start))
        return [self fail:@"发送仪表握手失败" error:error];
    NSMutableData *pending = [NSMutableData data];
    double deadline = uptime() + 8;
    while (uptime() < deadline && !_width) {
        struct pollfd wait = {_tcp, POLLIN, 0};
        int timeout = MAX(1, (int)((deadline - uptime()) * 1000));
        int status = poll(&wait, 1, timeout);
        if (status < 0 && errno == EINTR) continue;
        if (status <= 0) break;
        uint8_t chunk[4096];
        ssize_t n = recv(_tcp, chunk, sizeof(chunk), 0);
        if (n <= 0) return [self fail:@"仪表控制连接中断" error:error];
        [pending appendBytes:chunk length:(NSUInteger)n];
        while (pending.length >= 12) {
            const uint8_t *p = pending.bytes;
            uint32_t len;
            memcpy(&len, p + 8, 4); len = ntohl(len);
            NSUInteger consume = 1;
            if (!memcmp(p,"YD",2) && len <= 4096) {
                consume = len + 15;
                if (pending.length < consume) break;
                if (p[7] == 0xf1) return [self fail:@"仪表拒绝握手" error:error];
                if (p[7] == 0x20 && len >= 8) {
                    int w = p[12]*256+p[13], h = p[14]*256+p[15];
                    if (w < 320 || w > 4096 || h < 160 || h > 2160)
                        return [self fail:@"仪表返回异常画布尺寸" error:error];
                    _width = w; _height = h; _fps = p[19] ? MIN(10,p[19]) : 10;
                    break;
                }
            }
            [pending replaceBytesInRange:NSMakeRange(0,consume) withBytes:NULL length:0];
        }
    }
    if (!_width) return [self fail:@"等待仪表 0x20 画布回复失败" error:error];
    _udp = connectSocket(addr, SOCK_DGRAM, 8889);
    if (_udp < 0) return [self fail:@"UDP 8889 初始化失败" error:error];
    _frame = 0;
    return YES;
}
- (int)frameRate { return _fps; }
- (CGSize)canvasSize { return CGSizeMake(_width, _height); }
- (BOOL)sendJPEG:(NSData *)jpeg error:(NSError **)error {
    if (_udp < 0 || !jpeg.length || jpeg.length > UINT32_MAX) return [self fail:@"无效的画面或连接" error:error];
        if (_frame && _frame % 10 == 0 && !sendClock(_tcp))
            return [self fail:@"TCP 校时失败" error:error];
    uint16_t crc = imageCRC(jpeg.bytes, jpeg.length);
        for (NSUInteger offset = 0; offset < jpeg.length; offset += 1434) {
            uint8_t packet[1469];
            uint32_t ms = (uint32_t)(uint64_t)(NSDate.date.timeIntervalSince1970 * 1000);
            size_t count = fragmentPacket(packet, jpeg.bytes, (uint32_t)jpeg.length,
                                          (uint32_t)offset, _frame, crc, ms);
            if (send(_udp, packet, count, 0) != (ssize_t)count)
                return [self fail:@"UDP 发送图片失败" error:error];
        }
        _frame++;
    return YES;
}
@end
