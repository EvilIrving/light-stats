//
//  DisplayPrivateAPI.h
//  Light Stats
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <IOKit/i2c/IOI2CInterface.h>

NS_ASSUME_NONNULL_BEGIN

typedef CFTypeRef IOAVService;

extern IOAVService _Nullable IOAVServiceCreateWithService(
    CFAllocatorRef _Nullable allocator,
    io_service_t service
);
extern IOReturn IOAVServiceReadI2C(
    IOAVService service,
    uint32_t chipAddress,
    uint32_t offset,
    void *outputBuffer,
    uint32_t outputBufferSize
);
extern IOReturn IOAVServiceWriteI2C(
    IOAVService service,
    uint32_t chipAddress,
    uint32_t dataAddress,
    void *inputBuffer,
    uint32_t inputBufferSize
);
extern CFDictionaryRef _Nullable CoreDisplay_DisplayCreateInfoDictionary(
    CGDirectDisplayID display
) CF_RETURNS_RETAINED;
extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);

NS_ASSUME_NONNULL_END
