#import <dispatch/dispatch.h>
#import <Foundation/Foundation.h>

#import "MABaseFuture.h"
#import "MAFuture.h"
#import "MAFutureInternal.h"
#import "MAMethodSignatureCache.h"


#define ENABLE_LOGGING 1

#if ENABLE_LOGGING
#define LOG(...) NSLog(__VA_ARGS__)
#else
#define LOG(...)
#endif

@implementation _MASimpleFuture

- (id)forwardingTargetForSelector: (SEL)sel
{
    LOG(@"%p forwardingTargetForSelector: %@, resolving future", self, NSStringFromSelector(sel));
#if ENABLE_LOGGING
    id resolvedFuture = [self resolveFuture];
    if (resolvedFuture == nil) {
        LOG(@"WARNING: [%@ resolveFuture] has returned nil. You must avoid to return nil objects from the block", NSStringFromClass(isa));
    }
    return resolvedFuture;
#else
    return [self resolveFuture];
#endif
}

- (NSMethodSignature *)methodSignatureForSelector: (SEL)sel
{
    return [[MAMethodSignatureCache sharedCache] cachedMethodSignatureForSelector: sel];
}

- (void)forwardInvocation: (NSInvocation *)inv
{
    // this gets hit if the future resolves to nil
    // zero-fill the return value
    char returnValue[[[inv methodSignature] methodReturnLength]];
    bzero(returnValue, sizeof(returnValue));
    [inv setReturnValue: returnValue];
}

@end


@interface _MABackgroundBlockFuture : _MASimpleFuture
{
}
@end

@implementation _MABackgroundBlockFuture

- (id)initWithBlock: (id (^)(void))block
{
    if((self = [self init]))
    {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [self setFutureValue: block()];
        });
    }
    return self;
}

- (id)resolveFuture
{
    return [self waitForFutureResolution];
}

@end


@implementation _MALazyBlockFuture

- (id)initWithBlock: (id (^)(void))block
{
    if((self = [self init]))
    {
        _block = [block copy];
    }
    return self;
}

- (void)dealloc
{
    [_block release];
    [super dealloc];
}

- (id)resolveFuture
{
    [_lock lock];
    if(![self futureHasResolved])
    {
        [self setFutureValueUnlocked: _block()];
        [_block release];
        _block = nil;
    }
    [_lock unlock];
    return _value;
}

@end

#undef MABackgroundFuture
id MABackgroundFuture(id (^block)(void))
{
    return [[[_MABackgroundBlockFuture alloc] initWithBlock: block] autorelease];
}

#undef MALazyFuture
id MALazyFuture(id (^block)(void))
{
    return [[[_MALazyBlockFuture alloc] initWithBlock: block] autorelease];
}

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
#if __IPHONE_OS_VERSION_MIN_REQUIRED > __IPHONE_3_2

@implementation _IKMemoryAwareFuture
@dynamic isObserving;

- (BOOL)isObserving {
    return isObserving;
}


- (void)setIsObserving:(BOOL)newIsObserving {
    [_lock lock];
    if (newIsObserving && isManuallyStopped) {
        isManuallyStopped = NO;
        if (_resolved) {
            // If future is resolved set isObserving back to YES.
            // Otherwise this will be set to YES just after resolving.
            [self setIsObservingUnlocked:YES];
        }
    }
    else if (!newIsObserving && !isManuallyStopped) {
        isManuallyStopped = YES;
        if (_resolved) {
            // If future is resolved set isObserving to NO.
            // Otherwise this is already set to NO.
            [self setIsObservingUnlocked:NO];
        }
    }
    [_lock unlock];
}


- (void)setIsObservingUnlocked:(BOOL)newIsObserving {
    
    if (isObserving != newIsObserving) {
        if (newIsObserving) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processMemoryWarning) 
                                                         name:UIApplicationDidReceiveMemoryWarningNotification 
                                                       object:nil];
        }
        else {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        }
        isObserving = newIsObserving;
    }
}


- (void)dealloc
{
    [self setIsObservingUnlocked:NO];
    [super dealloc];
}


- (id)resolveFuture
{
    [_lock lock];
    if(![self futureHasResolved])
    {
        [self setFutureValueUnlocked: _block()];
        if (!isManuallyStopped) {
            [self setIsObservingUnlocked:YES];
        }
    }
    [_lock unlock];
    return _value;
}


- (void)processMemoryWarning {
    [_lock lock];
    // TODO: I'm not sure about the thread that receives UIApplicationDidReceiveMemoryWarningNotification.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self processMemoryWarningUnlocked];
        dispatch_async(dispatch_get_main_queue(), ^{ [_lock unlock]; });
    });
}


- (void)processMemoryWarningUnlocked {
    [self setIsObservingUnlocked:NO];
    [_value release], _value = nil;
    _resolved = NO;
}

@end

#undef IKMemoryAwareFutureCreate
id IKMemoryAwareFutureCreate(id (^block)(void)) {
    return [[_IKMemoryAwareFuture alloc] initWithBlock:block];
}

#undef IKMemoryAwareFuture
id IKMemoryAwareFuture(id (^block)(void)) {
    return [IKMemoryAwareFutureCreate(block) autorelease];
}

void IKMemoryAwareFutureStartObserving(id future) {
    [future setIsObserving:YES];
}

void IKMemoryAwareFutureStopObserving(id future) {
    [future setIsObserving:NO];
}

BOOL IKMemoryAwareFutureIsObserving(id future) {
    return [future isObserving];
}

#pragma mark -
#pragma mark Archiving IKMAFutures

NSString* IKMemoryAwareFuturesDirectory() {
    static NSString* FuturesDirectory = nil;
    if (FuturesDirectory == nil) {
        FuturesDirectory = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"futures"] retain];
    }
    return FuturesDirectory;
}

NSString* IKMemoryAwareFuturePath(id future) {
    return [IKMemoryAwareFuturesDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%p", future]];
}

@implementation _IKAutoArchivingMemoryAwareFuture

+ (void)initialize {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *futuresDirectory = IKMemoryAwareFuturesDirectory();
#if ENABLE_LOGGING
    NSError *error = nil;
    if (![fileManager removeItemAtPath:futuresDirectory error:&error]) {
        LOG(@"IKAAMAF: Error is occured while trying to remove old futures directory at path \"%@\": %@",
            futuresDirectory, [error localizedDescription]);
    }
    if (![fileManager createDirectoryAtPath:futuresDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
        LOG(@"IKAAMAF: Error is occured while trying to create temporary directory for futures at path \"%@\": %@",
            futuresDirectory, [error localizedDescription]);
    };
#else
    [fileManager removeItemAtPath:futuresDirectory error:NULL];
    [fileManager createDirectoryAtPath:futuresDirectory withIntermediateDirectories:NO attributes:nil error:NULL];
#endif
}


- (void)dealloc {
#if ENABLE_LOGGING
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:IKMemoryAwareFuturePath(self) error:&error]) {
        LOG(@"IKAAMAF: Error is occured while trying to delete file for future %@ at path \"%@\": %@", 
            self, IKMemoryAwareFuturePath(self), [error localizedDescription]);
    };
#else
    [[NSFileManager defaultManager] removeItemAtPath:IKMemoryAwareFuturePath(self) error:NULL];
#endif
    [super dealloc];
}


- (id)resolveFuture
{
    [_lock lock];
    if(![self futureHasResolved])
    {
        // Try to decode object from file.
        if (![self decodeValueUnlocked]) {
            // If cannot to decode object, create it.
            [self setFutureValueUnlocked: _block()];
        }
        if (!isManuallyStopped) {
            [self setIsObservingUnlocked:YES];
        }
    }
    [_lock unlock];
    return _value;
}


- (void)processMemoryWarningUnlocked {
    [self encodeValueUnlocked];
    [super processMemoryWarningUnlocked];
}


- (BOOL)encodeValue {
    [_lock lock];
    BOOL result = [self encodeValueUnlocked];
    [_lock unlock];
    return result;
}


- (BOOL)encodeValueUnlocked {
#if ENABLE_LOGGING
    BOOL result = [NSKeyedArchiver archiveRootObject:_value toFile:IKMemoryAwareFuturePath(self)];
    if (!result) {
        LOG(@"IKAAMAF: Cannot encode value at path \"%@\"", IKMemoryAwareFuturePath(self));
    }
    return result;
#else
    return [NSKeyedArchiver archiveRootObject:_value toFile:IKMemoryAwareFuturePath(self)];
#endif
}


- (BOOL)decodeValue {
    [_lock lock];
    BOOL result = [self decodeValueUnlocked];
    [_lock unlock];
    return result;
}


- (BOOL)decodeValueUnlocked {
    _value = [[NSKeyedUnarchiver unarchiveObjectWithFile:IKMemoryAwareFuturePath(self)] retain];
#if ENABLE_LOGGING
    if (_value == nil) {
        LOG(@"IKAAMAF: Cannot decode value at path \"%@\"", IKMemoryAwareFuturePath(self));
    }
#endif
    return (_value != nil);
}

@end

#undef IKAutoArchivingMemoryAwareFutureCreate
id IKAutoArchivingMemoryAwareFutureCreate(id (^block)(void)) {
    // TODO: Find a way to check up the object is returned by the block conforms to the NSCoding protocol.
    _IKAutoArchivingMemoryAwareFuture *future = [[_IKAutoArchivingMemoryAwareFuture alloc] initWithBlock:block];
    [future setIsObservingUnlocked:YES];
    return future;
}

#undef IKAutoArchivingMemoryAwareFuture
id IKAutoArchivingMemoryAwareFuture(id (^block)(void)) {
    return [IKAutoArchivingMemoryAwareFutureCreate(block) autorelease];
}

#endif // __IPHONE_OS_VERSION_MIN_REQUIRED > __IPHONE_3_2
#endif // __IPHONE_OS_VERSION_MIN_REQUIRED
