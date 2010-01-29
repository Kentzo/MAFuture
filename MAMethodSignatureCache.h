#import <Foundation/Foundation.h>


@interface MAMethodSignatureCache : NSObject
{
    NSMapTable *_cache;
    NSLock *_lock;
}

+ (MAMethodSignatureCache *)sharedCache;
- (NSMethodSignature *)cachedMethodSignatureForSelector: (SEL)sel;

@end
