//
//  YJHook.m
//  YJHook
//
//  Created by symbio on 2021/9/30.
//

#import "YJHook.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <libkern/OSAtomic.h>

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

#pragma mark - Block Helpers
#if !defined(NS_BLOCK_ASSERTIONS)

// See http://clang.llvm.org/docs/Block-ABI-Apple.html#high-level
struct Block_literal_1 {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct Block_descriptor_1 {
        unsigned long int reserved;         // NULL
        unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
        void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
        void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

enum {
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_HAS_STRET =         (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE =     (1 << 30),
};
typedef int BlockFlags;

static const char *blockGetType(id block) {
    struct Block_literal_1 *blockRef = (__bridge struct Block_literal_1 *)block;
    BlockFlags flags = blockRef->flags;
    
    if (flags & BLOCK_HAS_SIGNATURE) {
        void *signatureLocation = blockRef->descriptor;
        signatureLocation += sizeof(unsigned long int);
        signatureLocation += sizeof(unsigned long int);
        
        if (flags & BLOCK_HAS_COPY_DISPOSE) {
            signatureLocation += sizeof(void(*)(void *dst, void *src));
            signatureLocation += sizeof(void (*)(void *src));
        }
        
        const char *signature = (*(const char **)signatureLocation);
        return signature;
    }
    
    return NULL;
}

static BOOL blockIsCompatibleWithMethodType(id block, const char *methodType) {
    
    const char *blockType = blockGetType(block);
    
    NSMethodSignature *blockSignature;
    
    if (0 == strncmp(blockType, (const char *)"@\"", 2)) {
        // Block return type includes class name for id types
        // while methodType does not include.
        // Stripping out return class name.
        char *quotePtr = strchr(blockType+2, '"');
        if (NULL != quotePtr) {
            ++quotePtr;
            char filteredType[strlen(quotePtr) + 2];
            memset(filteredType, 0, sizeof(filteredType));
            *filteredType = '@';
            strncpy(filteredType + 1, quotePtr, sizeof(filteredType) - 2);
            
            blockSignature = [NSMethodSignature signatureWithObjCTypes:filteredType];
        } else {
            return NO;
        }
    } else {
        blockSignature = [NSMethodSignature signatureWithObjCTypes:blockType];
    }
    
    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodType];
    
    if (!blockSignature || !methodSignature) {
        return NO;
    }
    
    if (blockSignature.numberOfArguments != methodSignature.numberOfArguments) {
        return NO;
    }
    
    if (strcmp(blockSignature.methodReturnType, methodSignature.methodReturnType) != 0) {
        return NO;
    }
    
    for (int i=0; i<methodSignature.numberOfArguments; ++i) {
        if (i == 0){
            // self in method, block in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], "@") != 0) {
                return NO;
            }
            if (strcmp([blockSignature getArgumentTypeAtIndex:i], "@?") != 0) {
                return NO;
            }
        } else if (i == 1){
            // SEL in method, self in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], ":") != 0) {
                return NO;
            }
            if (strncmp([blockSignature getArgumentTypeAtIndex:i], "@", 1) != 0) {
                return NO;
            }
        } else {
            const char *blockSignatureArg = [blockSignature getArgumentTypeAtIndex:i];
            
            if (strncmp(blockSignatureArg, "@?", 2) == 0) {
                // Handle function pointer / block arguments
                blockSignatureArg = "@?";
            }
            else if (strncmp(blockSignatureArg, "@", 1) == 0) {
                blockSignatureArg = "@";
            }
            
            if (strcmp(blockSignatureArg,
                       [methodSignature getArgumentTypeAtIndex:i]) != 0)
            {
                return NO;
            }
        }
    }
    
    return YES;
}

static BOOL blockIsAnImpFactoryBlock(id block) {
    const char *blockType = blockGetType(block);
    YJHookImpFactoryBlock dummyFactory = ^id(YJHookInfo *swizzleInfo){
        return nil;
    };
    const char *factoryType = blockGetType(dummyFactory);
    return 0 == strcmp(factoryType, blockType);
}

#endif // NS_BLOCK_ASSERTIONS

typedef NS_ENUM(NSUInteger, YJHookMode) {
    /// YJHook always does swizzling.
    YJHookModeAlways = 0,
    /// YJHook does not do swizzling if the same class has been swizzled earlier with the same key.
    YJHookModeOncePerClass = 1,
    /// YJHook does not do swizzling if the same class or one of its superclasses have been swizzled earlier with the same key.
    /// @note There is no guarantee that your implementation will be called only once per method call. If the order of swizzling is: first inherited class, second superclass, then both swizzlings will be done and the new implementation will be called twice.
    YJHookModeOncePerClassAndSuperclasses = 2
};

#pragma mark - Swizzling
typedef IMP (^YJHookImpProvider)(void);

@interface YJHookInfo()
@property (nonatomic, copy) YJHookImpProvider impProviderBlock;
@property (nonatomic, readwrite) SEL selector;
@property (nonatomic, readwrite) BOOL originalImpExists;
@end

@implementation YJHookInfo

- (YJHookOriginalIMP)originalImplementation {
    NSAssert(_originalImpExists, @"DO NOT call original IMP");
    NSAssert(_impProviderBlock, nil);
    // Casting IMP to YJHookOriginalIMP to force user casting.
    return (YJHookOriginalIMP)_impProviderBlock();
}

@end

@implementation YJHook

static BOOL isMsgForwardIMP(IMP impl) {
    return impl == _objc_msgForward
#if !defined(__arm64__)
    || impl == (IMP)_objc_msgForward_stret
#endif
    ;
}

/// method 是否允许hook
static BOOL isAllowHook(Method method) {
    return NULL == method || !isMsgForwardIMP(method_getImplementation(method));
}

static BOOL swizzle(Class classToSwizzle,
                    SEL selector,
                    Method method,
                    YJHookImpFactoryBlock factoryBlock) {
    if (NULL == method) {
        method = class_getInstanceMethod(classToSwizzle, selector);
    }
    BOOL originalImpExists = method != NULL;
    
    NSCAssert(blockIsAnImpFactoryBlock(factoryBlock), @"Wrong type of implementation factory block.");
    
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);
    __block IMP originalIMP = NULL;

    // 这个block由客户端调用来返回原始实现
    YJHookImpProvider originalImpProvider = ^IMP{
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        IMP imp = originalIMP;
        dispatch_semaphore_signal(semaphore);
        
        if (NULL == imp) {
            /**
             imp为NULL表明classToSwizzle中原来没有实现selector
             此刻method_getImplementation((class_getInstanceMethod(classToSwizzle, selector))返回值为新添加的实现
             直接从classToSwizzle向上查找会造成死循环，所以需要从其直接父类中查找
             **/
            Class superclass = class_getSuperclass(classToSwizzle);
            imp = method_getImplementation(class_getInstanceMethod(superclass,selector));
        }
        return imp;
    };
    
    YJHookInfo *swizzleInfo = [YJHookInfo new];
    swizzleInfo.selector = selector;
    swizzleInfo.impProviderBlock = originalImpProvider;
    swizzleInfo.originalImpExists = originalImpExists;
    
    // swizzleInfo 包含如何被交换的方法的selector，如果获取被交换方法的原始实现，是否存在原始实现
    id newIMPBlock = factoryBlock(swizzleInfo);
    
    const char *methodType = method_getTypeEncoding(method);
    
    // 在classToSwizzle中没有实现selector时，缺少block类型与方法类型的兼容性校验
    if (originalImpExists) {
        NSCAssert(blockIsCompatibleWithMethodType(newIMPBlock,methodType),
                  @"Block returned from factory is not compatible with method type.");
    }
    
    IMP newIMP = imp_implementationWithBlock(newIMPBlock);
    BOOL allowHook = isAllowHook(method);
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    /**
     如果原始方法不存在，methodType为空值。
     
     不能从block的类型编码中，获取带偏移的原始实现的方法签名。
     待验证不带偏移的方法签名传入types参数效果如何。
     **/
    if (allowHook) {
        originalIMP = class_replaceMethod(classToSwizzle, selector, newIMP, methodType);
    }
    dispatch_semaphore_signal(semaphore);
    
    return allowHook;
}

static NSMutableDictionary *swizzledClassesDictionary() {
    static NSMutableDictionary *swizzledClasses;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzledClasses = [NSMutableDictionary new];
    });
    return swizzledClasses;
}

static NSMutableSet *swizzledClassesForKey(const void *key) {
    NSMutableDictionary *classesDictionary = swizzledClassesDictionary();
    NSValue *keyValue = [NSValue valueWithPointer:key];
    NSMutableSet *swizzledClasses = [classesDictionary objectForKey:keyValue];
    if (!swizzledClasses) {
        swizzledClasses = [NSMutableSet new];
        [classesDictionary setObject:swizzledClasses forKey:keyValue];
    }
    return swizzledClasses;
}

static dispatch_semaphore_t swizzledClassesDictionarySemaphore() {
    static dispatch_semaphore_t semaphore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        semaphore = dispatch_semaphore_create(1);
    });
    return semaphore;
}

static void waitSwizzledClassesDictionary() {
    dispatch_semaphore_wait(swizzledClassesDictionarySemaphore(), DISPATCH_TIME_FOREVER);
}

static void signalSwizzledClassesDictionary() {
    dispatch_semaphore_signal(swizzledClassesDictionarySemaphore());
}

/**
 查询某个类本身是否实现了指定的方法
 
 @param cls 以Person类为例，如果查询的是其实例方法，那么cls值应该是[Person class]；
 如果查询的是其类方法，那么cls值应该是object_getClass([Person class])。
 */
static BOOL methodExistsInClassMethodList(SEL methodName, Class cls, Method *outMethod) {
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(cls, &methodCount);
    Method *method = NULL;
    BOOL exists = false;
    for (unsigned int i = 0; i < methodCount; i++) {
        method = methodList + i;
        if (method_getName(*method) == methodName) {
            exists = true;
            if (outMethod) {
                *outMethod = *method;
            }
            break;
        }
    }
    if (NULL != methodList) {
        free(methodList);
    }
    return exists;
}

static Class getDestinationClass(SEL selector, Class classToSwizzle, BOOL forceImplement, Method *outMethod) {
    Class destinationClass = Nil;
    for (Class currentClass = classToSwizzle; Nil != currentClass; currentClass = class_getSuperclass(currentClass)) {
        BOOL methodExists = methodExistsInClassMethodList(selector, currentClass, outMethod);
        if (methodExists) {
            destinationClass = currentClass;
            break;
        }
    }
    if (forceImplement && destinationClass == Nil) {
        destinationClass = classToSwizzle;
    }
    return destinationClass;
}

/**
 进行方法交换
 
 @param selector 需要交换的方法的selector
 @param classToSwizzle 需要交换的方法所在的类，classToSwizzle是真正要进行hook的类
 @param method selector在classToSwizzle中查到Method
 */
+(BOOL)swizzleInstanceMethod:(SEL)selector
                     inClass:(Class)classToSwizzle
                      method:(Method)method
               newImpFactory:(YJHookImpFactoryBlock)factoryBlock
                        mode:(YJHookMode)mode
                         key:(const void *)key {
    NSAssert(!(NULL == key && YJHookModeAlways != mode),
             @"Key may not be NULL if mode is not RSSwizzleModeAlways.");
    
    waitSwizzledClassesDictionary();
    if (key) {
        NSSet *swizzledClasses = swizzledClassesForKey(key);
        if (mode == YJHookModeOncePerClass) {
            if ([swizzledClasses containsObject:classToSwizzle]) {
                signalSwizzledClassesDictionary();
                return YES;
            }
        } else if (mode == YJHookModeOncePerClassAndSuperclasses) {
            for (Class currentClass = classToSwizzle;
                 Nil != currentClass;
                 currentClass = class_getSuperclass(currentClass)) {
                if ([swizzledClasses containsObject:currentClass]) {
                    signalSwizzledClassesDictionary();
                    return YES;
                }
            }
        }
    }
    
    BOOL success = swizzle(classToSwizzle, selector, method, factoryBlock);
    
    if (key) {
        [swizzledClassesForKey(key) addObject:classToSwizzle];
    }
    signalSwizzledClassesDictionary();
    
    return success;
}

+ (BOOL)swizzleInstanceMethod:(SEL)selector
                      inClass:(Class)classToSwizzle
               forceImplement:(BOOL)forceImplement
          destinationClsssPtr:(Class *)destinationClassPtr
                          key:(const void *)key
                newImpFactory:(YJHookImpFactoryBlock)factoryBlock {
    const void *uniqueKey = key;
    if (NULL == uniqueKey) {
        uniqueKey = selector;
    }
    
    Method method = NULL;
    Class destinationClass = getDestinationClass(selector, classToSwizzle, forceImplement, &method);
    if (destinationClassPtr) {
        *destinationClassPtr = destinationClass;
    }
    if (Nil == destinationClass) {
        return NO;
    }
    if (!isAllowHook(method)) {
        return NO;
    }
    
    return [YJHook swizzleInstanceMethod:selector
                                     inClass:destinationClass
                                      method:method
                               newImpFactory:factoryBlock
                                        mode:YJHookModeOncePerClass
                                         key:uniqueKey];
}

+ (BOOL)swizzleInstanceMethod:(SEL)selector
                      inClass:(Class)classToSwizzle
               forceImplement:(BOOL)forceImplement
                newImpFactory:(YJHookImpFactoryBlock)factoryBlock {
    return [self swizzleInstanceMethod:selector
                               inClass:classToSwizzle
                        forceImplement:forceImplement
                   destinationClsssPtr:nil
                                   key:NULL
                         newImpFactory:factoryBlock];
}

+ (BOOL)swizzleClassMethod:(SEL)selector
                   inClass:(Class)classToSwizzle
            forceImplement:(BOOL)forceImplement
             newImpFactory:(YJHookImpFactoryBlock)factoryBlock {
    return [self swizzleInstanceMethod:selector
                               inClass:object_getClass(classToSwizzle)
                        forceImplement:forceImplement
                         newImpFactory:factoryBlock];
}

@end
