//
//  YJHook.h
//  YJHook
//
//  Created by symbio on 2021/9/30.
//

#import <Foundation/Foundation.h>

/**
 指向被交换的方法的原始实现的函数指针类型
 */
typedef void (*YJHookOriginalIMP)(void /* id, SEL, ... */ );

/**
 在新实现的block中，YJHookInfo被用于获取被交换方法的原始实现，以便在新实现中调用原始实现。
 */
@interface YJHookInfo : NSObject

/// 被交换的方法的原始实现
@property (nonatomic, readonly) YJHookOriginalIMP originalImplementation;

/// 被交换的方法对应的selector
@property (nonatomic, readonly) SEL selector;

/**
 是否需要调用原始实现
 
 @note 在 newImpBlock 中一定要判断该值是否为真，只有为真的情况才可以获取原始实现并调用。
 
       在 classToSwizzle 及其父类中都没有实现 selector，也就是交换的方法不能通过
       class_getInstanceMethod(classToSwizzle, selector) 获取的情况下，该值为假。
 */
@property (nonatomic, readonly) BOOL originalImpExists;

@end

/**
 factory block，返回值是被交换的方法的新的实现的block。

 @param hookInfo 提供用于获取被交换的方法的原始实现的信息
 @return 返回新实现的block
 
 @note 返回的block的签名一定要与原始实现的方法签名一致。
 
       假设原始实现的方法签名是：`method_return_type ^(id self, SEL _cmd, method_args..)`，
       那么返回的block签名应该为：`method_return_type ^(id self, method_args...)`。
 */
typedef id (^YJHookImpFactoryBlock)(YJHookInfo *hookInfo);

@interface YJHook : NSObject

/**
交换实例方法的实现

@note 最终交换的方法所在的类不一定是传入的classToSwizzle

内部逻辑：
   1. 在该类及其父类中查找最近的实现了selector的类A，如果该类及其父类中都没有实现selector，且forceImplement为真，那么类A赋值为classToSwizzle；

   2. 如果该类及其父类中都没有实现selector，如果forceImplement为false，hook失败；
      如果forceImplement为true，那么在classToSwizzle中添加新的实现，新的实现由factoryBlock返回的block生成；

      在forceImplement为true的情况下：

      假设继承关系 A <-- B <-- C，A 实现了 foo 方法、B 中覆盖了 A 的实现 foo 方法，C 中没有覆盖 foo 方法。
      那么在针对 C 类中的 foo 方法中 hook 时，实际上交换的是 B 中的 foo 方法。

      假设继承关系 A <-- B <-- C，A、B、C 中都没有实现 foo 方法。
      那么在针对 C 类中的 foo 方法中 hook 时，实际上是为 C 添加新的实现。

@param selector 要交换的方法名
@param classToSwizzle 要交换的方法所在的类
@param factoryBlock 用于返回新实现block的factory block，要注意该factory block返回的新实现的block要与被交换的方法的原始实现的签名兼容
@param forceImplement 是否强制实现
@param destinationClassPtr 真正hook的类（出参）
@param key 方法交换的key，用于保证只hook一次。如果key为NULL，那么内部取selector作为key。
@return 在forceImplement为假，且classToSwizzle及其父类中都没有实现selector的情况下，返回假；其余情况，都返回真。
*/
+ (BOOL)swizzleInstanceMethod:(SEL)selector
                      inClass:(Class)classToSwizzle
               forceImplement:(BOOL)forceImplement
          destinationClsssPtr:(Class *)destinationClassPtr
                          key:(const void *)key
                newImpFactory:(YJHookImpFactoryBlock)factoryBlock;

/**
 相当于:
 `[self swizzleInstanceMethod:selector
                inClass:classToSwizzle
          forceImplement:forceImplement
       destinationClsssPtr:nil
                key:NULL
          newImpFactory:factoryBlock]`
 */
+ (BOOL)swizzleInstanceMethod:(SEL)selector
                      inClass:(Class)classToSwizzle
               forceImplement:(BOOL)forceImplement
                newImpFactory:(YJHookImpFactoryBlock)factoryBlock;


/**
 交换类方法的实现，相当于：
 [self swizzleInstanceMethod:selector
                inClass:object_getClass(classToSwizzle)
          forceImplement:forceImplement
          newImpFactory:factoryBlock]`
 */
+ (BOOL)swizzleClassMethod:(SEL)selector
                   inClass:(Class)classToSwizzle
            forceImplement:(BOOL)forceImplement
             newImpFactory:(YJHookImpFactoryBlock)factoryBlock;

@end


#pragma mark - Macros Based API

/// A macro for wrapping the return type of the swizzled method.
#define YJReturnType(type) type

#define YJForceImplement(forceImplement) forceImplement

/// A macro for wrapping arguments of the swizzled method.
#define YJArguments(arguments...) _YJArguments(arguments)

/// A macro for wrapping the replacement code for the swizzled method.
#define YJReplacement(code...) code

/// A macro for casting and calling original implementation.
/// May be used only in YJHookInstanceMethod or YJHookClassMethod macros.
#define YJCallOriginal(arguments...) _YJCallOriginal(arguments)

#pragma mark └ Swizzle Instance Method

#define YJHookInstanceMethod(classToSwizzle, \
                            selector, \
                            YJReturnType, \
                            YJArguments, \
                            YJForceImplement, \
                            YJReplacement) \
_YJHookInstanceMethod(classToSwizzle, \
                         selector, \
                         YJReturnType, \
                         _YJWrapArg(YJArguments), \
                         _YJWrapArg(YJForceImplement), \
                         _YJWrapArg(YJReplacement))

#pragma mark └ Swizzle Class Method

#define YJHookClassMethod(classToSwizzle, \
                            selector, \
                            YJReturnType, \
                            YJArguments, \
                            YJForceImplement, \
                            YJReplacement) \
_YJHookClassMethod(classToSwizzle, \
                         selector, \
                         YJReturnType, \
                         _YJWrapArg(YJArguments), \
                         _YJWrapArg(YJForceImplement), \
                         _YJWrapArg(YJReplacement))

#pragma mark - Implementation details
// 不要编写依赖于这一行以下内容的代码。

// 包装参数，将它们作为单个参数传递给另一个宏。
#define _YJWrapArg(args...) args

#define _YJDel2Arg(a1, a2, args...) a1, ##args
#define _YJDel3Arg(a1, a2, a3, args...) a1, a2, ##args

// To prevent comma issues if there are no arguments we add one dummy argument
// and remove it later.
#define _YJArguments(arguments...) DEL, ##arguments

#define _YJHookInstanceMethod(classToSwizzle, \
                                selector, \
                                YJReturnType, \
                                YJArguments, \
                                YJForceImplement, \
                                YJReplacement) \
    [YJHook \
        swizzleInstanceMethod:selector \
        inClass:classToSwizzle \
        forceImplement:YJForceImplement \
        newImpFactory:^id(YJHookInfo *swizzleInfo) { \
           YJReturnType (*originalImplementation_)(_YJDel3Arg(__unsafe_unretained id, \
                                                                  SEL, \
                                                                  YJArguments)); \
           SEL selector_ = selector; \
           return ^YJReturnType (_YJDel2Arg(__unsafe_unretained id SELF, \
                                                YJArguments)) \
           { \
               YJReplacement \
           }; \
        } \
    ];

#define _YJHookClassMethod(classToSwizzle, \
                              selector, \
                              YJReturnType, \
                              YJArguments, \
                              YJForceImplement, \
                              YJReplacement) \
    [YJHook \
        swizzleClassMethod:selector \
        inClass:classToSwizzle \
        forceImplement:YJForceImplement \
        newImpFactory:^id(YJHookInfo *swizzleInfo) { \
           YJReturnType (*originalImplementation_)(_YJDel3Arg(__unsafe_unretained id, \
                                                                  SEL, \
                                                                  YJArguments)); \
           SEL selector_ = selector; \
           return ^YJReturnType (_YJDel2Arg(__unsafe_unretained id SELF, \
                                                YJArguments)) \
           { \
               YJReplacement \
           }; \
        } \
    ];

#define _YJCallOriginal(arguments...) \
    ((__typeof(originalImplementation_))[swizzleInfo \
                                         originalImplementation])(SELF, \
                                                                     selector_, \
                                                                     ##arguments)
