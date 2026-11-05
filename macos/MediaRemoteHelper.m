// Puente a MediaRemote (framework privado) que se carga dentro de /usr/bin/perl.
//
// Desde macOS 15.4, MediaRemote sólo responde a procesos firmados por Apple, así que la app ya no
// puede leer qué suena en TIDAL, Deezer, navegadores, etc. /usr/bin/perl sí está firmado por Apple:
// la app lo lanza, perl carga esta biblioteca con DynaLoader y llama a `mad_mediaremote`, que
// escribe en stdout una línea JSON por segundo con lo que está sonando (o `null`).
//
// Por stdin recibe comandos, uno por línea (número de MRCommand: 2 play/pausa, 4 siguiente,
// 5 anterior). El proceso sigue vivo, así que el mensaje a MediaRemote llega aunque sea asíncrono.
// Cuando stdin se cierra (la app terminó) el proceso sale.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef void (*InfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*PidFn)(dispatch_queue_t, void (^)(int));
typedef void (*PlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*CommandFn)(int, CFDictionaryRef);

static InfoFn getInfo;
static CommandFn sendCommand;
static PidFn getPid;
static PlayingFn getPlaying;

static NSString *str(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static double num(id v) { return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0; }

static void emit(id obj) {
    @autoreleasepool {
        NSData *data = obj ? [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil] : nil;
        if (data) fwrite(data.bytes, 1, data.length, stdout); else fputs("null", stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}

/// Lee de stdin y envía cada comando completo; con EOF (la app se cerró) termina.
static void readCommands(void) {
    static char line[64];
    static size_t len = 0;
    char buf[64];
    ssize_t n = read(STDIN_FILENO, buf, sizeof buf);
    if (n <= 0) exit(0);
    for (ssize_t i = 0; i < n; i++) {
        if (buf[i] == '\n') {
            line[len] = 0;
            len = 0;
            int cmd = atoi(line);
            if (cmd > 0 && sendCommand) sendCommand(cmd, NULL);
        } else if (len < sizeof line - 1) {
            line[len++] = buf[i];
        }
    }
}

static void poll(dispatch_queue_t q) {
    // Si la app que nos lanzó ya no existe, no tiene sentido seguir.
    if (getppid() == 1) exit(0);
    getPid(q, ^(int pid) {
        getPlaying(q, ^(Boolean playing) {
            getInfo(q, ^(CFDictionaryRef ref) {
                NSDictionary *d = (__bridge NSDictionary *)ref;
                NSString *title = str(d[@"kMRMediaRemoteNowPlayingInfoTitle"]);
                if (pid <= 0 || title.length == 0) { emit(nil); return; }
                id ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                double stamp = [ts isKindOfClass:NSDate.class] ? [ts timeIntervalSince1970] : 0;
                emit(@{
                    @"pid": @(pid),
                    @"playing": @(playing ? YES : NO),
                    @"title": title,
                    @"artist": str(d[@"kMRMediaRemoteNowPlayingInfoArtist"]),
                    @"album": str(d[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
                    @"duration": @(num(d[@"kMRMediaRemoteNowPlayingInfoDuration"])),
                    @"elapsed": @(num(d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])),
                    @"rate": @(num(d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"])),
                    @"timestamp": @(stamp),
                });
            });
        });
    });
}

// Firma de una XSUB de perl (pTHX_ CV*); los argumentos no se usan y la función no vuelve.
__attribute__((visibility("default")))
void mad_mediaremote(void *perl, void *cv) {
    (void)perl; (void)cv;
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!h) exit(2);

    sendCommand = (CommandFn)dlsym(h, "MRMediaRemoteSendCommand");
    getInfo = (InfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    getPid = (PidFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
    getPlaying = (PlayingFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getInfo || !getPid || !getPlaying) exit(3);

    dispatch_queue_t q = dispatch_get_main_queue();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(timer, ^{ poll(q); });
    dispatch_resume(timer);
    dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, q);
    dispatch_source_set_event_handler(input, ^{ readCommands(); });
    dispatch_resume(input);
    dispatch_main();
}
