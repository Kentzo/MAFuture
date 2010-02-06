// gcc -framework Foundation -W -Wall -Wno-unused-parameter --std=c99 -g *.m
#import <Foundation/Foundation.h>

#import <objc/runtime.h>
#import "MACompoundFuture.h"
#import "MAFuture.h"

// make NSLog properly reentrant
#define NSLog(...) NSLog(@"%@", [NSString stringWithFormat: __VA_ARGS__])


@implementation NSObject (ObjectReturnAndPrimitiveByReference)

+ (NSString *)objectReturnAndPrimitiveByReference: (int *)outInt
{
    if(outInt)
        *outInt = 42;
    return @"object";
}

@end

static void TestOutParameters(void)
{
    NSLog(@"Testing out parameters");

    Class nsstring = MACompoundFuture(^{ usleep(100000); return [NSString class]; });
    NSLog(@"string: %p", [nsstring string]);
    
    NSError *baderr = nil;
    NSString *badstr = [nsstring stringWithContentsOfFile: @"/this/file/does/not/exist" encoding: NSUTF8StringEncoding error: &baderr];
    NSError *gooderr = nil;
    NSString *goodstr = [nsstring stringWithContentsOfFile: @"/etc/passwd" encoding: NSUTF8StringEncoding error: &gooderr];
    NSLog(@"stringWithContentsOfFile, pointers: %p error: %p", badstr, baderr);
    NSLog(@"stringWithContentsOfFile, descriptions: %@ error: %@", badstr, baderr);
    NSLog(@"stringWithContentsOfFile, pointers: %p error: %p", goodstr, gooderr);
    NSLog(@"stringWithContentsOfFile, descriptions: %@ error: %@", [goodstr substringToIndex: 2], gooderr);
    
    
    Class nsobject = MACompoundFuture(^{ usleep(100000); return [NSObject class]; });
    int x = 0;
    NSString *str = [nsobject objectReturnAndPrimitiveByReference: &x];
    NSLog(@"objectReturnAndPrimitiveByReference pointer: %p int: %d", str, x);
    NSLog(@"objectReturnAndPrimitiveByReference description: %@ int: %d", str, x);
}

int main(int argc, char **argv)
{
    [NSAutoreleasePool new];
    
    @try
    {
        NSLog(@"start");
        NSString *future = MAFuture(^{
            NSLog(@"Computing future\n");
            usleep(100000);
            return @"future result";
        });
        NSLog(@"future created");
        NSString *lazyFuture = MALazyFuture(^{
            NSLog(@"Computing lazy future\n");
            usleep(100000);
            return @"lazy future result";
        });
        NSLog(@"lazy future created");
        NSString *compoundFuture = MACompoundFuture(^{
            NSLog(@"Computing compound future\n");
            usleep(100000);
            return @"compound future result";
        });
        NSLog(@"compound future created");
        NSString *compoundLazyFuture = MACompoundLazyFuture(^{
            NSLog(@"Computing compound lazy future\n");
            usleep(100000);
            return @"compound future result";
        });
        NSLog(@"compound lazy future created");
        
        id nilFuture = MAFuture(^{ return nil; });
        id nilCompoundFuture = MACompoundFuture(^{ return nil; });
        
        NSLog(@"future: %@", future);
        NSLog(@"lazy future: %@", lazyFuture);
        NSLog(@"compound future: %@", [compoundFuture stringByAppendingString: @" suffix"]);
        NSLog(@"compound lazy future: %@", [compoundLazyFuture stringByAppendingString: @" suffix"]);
        
        NSString *future1 = MAFuture(^{
            NSLog(@"Computing future\n");
            usleep(100000);
            return @"future result";
        });
        NSString *future2 = MAFuture(^{
            NSLog(@"Computing future\n");
            usleep(100000);
            return @"future result";
        });
        NSLog(@"%p == %p? %llx %llx %s", future1, future2, (long long)[future1 hash], (long long)[future2 hash], [future1 isEqual: future2] ? "YES" : "NO");
        NSLog(@"nil future: %@", nilFuture);
        NSLog(@"nil compound future: %@", nilCompoundFuture);
        
        TestOutParameters();
    }
    @catch(id exception)
    {
        fprintf(stderr, "Exception: %s\n", [[exception description] UTF8String]);
    }
    
//    unsigned int count;
//    Method *list = class_copyMethodList([NSProxy class], &count);
//    for(unsigned i = 0; i < count; i++)
//        NSLog(@"%@", NSStringFromSelector(method_getName(list[i])));
}

