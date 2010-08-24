#import "MABaseFuture.h"


@interface _MASimpleFuture : MABaseFuture
{
}
@end

@interface _MALazyBlockFuture : _MASimpleFuture
{
    id (^_block)(void);
}

- (id)initWithBlock: (id (^)(void))block;

@end

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_4_0

@interface _IKMemoryAwareFuture : _MALazyBlockFuture {
    BOOL isObserving;
}

@property BOOL isObserving;

- (void)memoryWarningHandler;

- (void)setIsObservingUnlocked:(BOOL)newIsObserving;

@end

#endif // __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_4_0
#endif // __IPHONE_OS_VERSION_MIN_REQUIRED
