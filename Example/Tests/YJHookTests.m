//
//  YJHookTests.m
//  YJHook_Tests
//
//  Created by symbio on 2021/9/30.
//  Copyright © 2021 562925462@qq.com. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <XCTest/XCTest.h>
#import "YJHook.h"
#import "YJTestLog.h"

@interface YJHookTestClass_A : NSObject
@end
@implementation YJHookTestClass_A
+ (void)hookClassMethod1 {
    [YJTestLog log:@"A"];
}
+ (void)hookClassMethod2 {
    [YJTestLog log:@"A"];
}
@end

@interface YJHookTestClass_B : YJHookTestClass_A
@end
@implementation YJHookTestClass_B
- (void)hookOnDemandMethod1 {
    [YJTestLog log:@"B"];
}
- (void)hookOnDemandMethod2 {
    [YJTestLog log:@"B"];
}
- (void)hookForcelyMethod1 {
    [YJTestLog log:@"B"];
}
- (void)hookForcelyMethod2 {
    [YJTestLog log:@"B"];
}
- (void)hookMethod1 {
    [YJTestLog log:@"B"];
}
- (void)hookMethod2 {
    [YJTestLog log:@"B"];
}
@end

@interface YJHookTestClass_C : YJHookTestClass_B
@end
@implementation YJHookTestClass_C
@end

@interface YJHookTestClass_D : YJHookTestClass_C
@end
@implementation YJHookTestClass_D
- (void)hookMethod1 {
    [YJTestLog log:@"D"];
}
- (void)hookMethod2 {
    [super hookMethod2];
    [YJTestLog log:@"D"];
}
@end

@interface YJHookTests : XCTestCase

@end

@implementation YJHookTests

// 按需hook，类本身及其父类都没有实现
- (void)testHookOnDemandOriginalNoImplement {
    BOOL success = [YJHook swizzleInstanceMethod:NSSelectorFromString(@"noExistsMethod")
                                             inClass:YJHookTestClass_A.class
                                      forceImplement:NO
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            originalIMP(SELF, swizzleInfo.selector);
        };
    }];
    
    XCTAssertFalse(success);
}

// 按需hook，父类有实现，类本身没有覆盖父类实现
- (void)testHookOnDemandImplementInSuper {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookOnDemandMethod2)
                                             inClass:YJHookTestClass_C.class
                                      forceImplement:NO
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"C'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"C'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_C new] hookOnDemandMethod2];
    XCTAssertTrue([YJTestLog is:@"C'1BC'2"]);
}

// 按需hook，在本类中实现（包含覆盖父类实现的情形）
- (void)testHookOnDemandImplementInSelf {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookOnDemandMethod1)
                                             inClass:YJHookTestClass_B.class
                                      forceImplement:NO
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"B'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"B'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_B new] hookOnDemandMethod1];
    XCTAssertTrue([YJTestLog is:@"B'1BB'2"]);
}

// 强行hook，没有实现
- (void)testHookForcelyNoImplement {
    [YJTestLog clear];
    
    SEL selector = NSSelectorFromString(@"errorMethodName");
    BOOL success = [YJHook swizzleInstanceMethod:selector
                                             inClass:YJHookTestClass_A.class
                                      forceImplement:YES
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            [YJTestLog log:@"1"];
            if (swizzleInfo.originalImpExists) {
                originalIMP = (typeof(originalIMP))[swizzleInfo originalImplementation];
                originalIMP(SELF, swizzleInfo.selector);
                [YJTestLog log:@"2"];
            }
            [YJTestLog log:@"3"];
        };
    }];
    XCTAssertTrue(success);
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [[YJHookTestClass_A new] performSelector:selector];
#pragma clang diagnostic pop
    XCTAssertTrue([YJTestLog is:@"13"]);
}

// 强行hook，在本类中实现
- (void)testHookForcelyHasImp {
    [YJTestLog clear];
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookForcelyMethod1)
                                             inClass:YJHookTestClass_B.class
                                      forceImplement:YES
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            [YJTestLog log:@"B'1"];
            if (swizzleInfo.originalImpExists) {
                void (*originalIMP)(__unsafe_unretained id, SEL);
                originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
                originalIMP(SELF, swizzleInfo.selector);
            }
            [YJTestLog log:@"B'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_B new] hookForcelyMethod1];
    XCTAssertTrue([YJTestLog is:@"B'1BB'2"]);
}

// 强行hook，在父类中实现
- (void)testHookForcelyImplementInSuper {
    [YJTestLog clear];
    
    Class destClass = Nil;
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookForcelyMethod2)
                                             inClass:YJHookTestClass_C.class
                                      forceImplement:YES
                                 destinationClsssPtr:&destClass
                                                 key:NULL
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            [YJTestLog log:@"C'1"];
            if (swizzleInfo.originalImpExists) {
                void (*originalIMP)(__unsafe_unretained id, SEL);
                originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
                originalIMP(SELF, swizzleInfo.selector);
            }
            [YJTestLog log:@"C'2"];
        };
    }];
    XCTAssertTrue(success);
    XCTAssertTrue(destClass == YJHookTestClass_B.class);
    
    [[YJHookTestClass_C new] hookForcelyMethod2];
    XCTAssertTrue([YJTestLog is:@"C'1BC'2"]);
}

// 要hook的方法在父类、子类中都有实现，先hook父类中的，再hook子类中的
- (void)testHookInSuperFirstly_ThenHookInSelf {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookMethod1)
                                             inClass:YJHookTestClass_B.class
                                      forceImplement:NO
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"B'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"B'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_B new] hookMethod1];
    XCTAssertTrue([YJTestLog is:@"B'1BB'2"]);
    
    [YJTestLog clear];
    
    success = [YJHook swizzleInstanceMethod:@selector(hookMethod1)
                                        inClass:YJHookTestClass_D.class
                                 forceImplement:NO
                                  newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"D'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"D'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_D new] hookMethod1];
    XCTAssertTrue([YJTestLog is:@"D'1DD'2"]);
}

// 要hook的方法在父类、子类中都有实现，先hook父类中的，再hook子类中的，在子类的实现中调用父类的实现
- (void)testHookInSuperFirstly_ThenHookInSelf_CallSuperInSubImp {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleInstanceMethod:@selector(hookMethod2)
                                             inClass:YJHookTestClass_B.class
                                      forceImplement:NO
                                       newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"B'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"B'2"];
        };
    }];
    XCTAssertTrue(success);
    
    success = [YJHook swizzleInstanceMethod:@selector(hookMethod2)
                                        inClass:YJHookTestClass_D.class
                                 forceImplement:NO
                                  newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"D'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"D'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [[YJHookTestClass_D new] hookMethod2];
    XCTAssertTrue([YJTestLog is:@"D'1B'1BB'2DD'2"]);
}

// hook类方法
- (void)testHookClassMethod {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleClassMethod:@selector(hookClassMethod1)
                                          inClass:YJHookTestClass_A.class
                                   forceImplement:NO
                                    newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"A'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"A'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [YJHookTestClass_A hookClassMethod1];
    XCTAssertTrue([YJTestLog is:@"A'1AA'2"]);
}

// hook类方法，原实现在父类中
- (void)testHookClassMethodInSuper {
    [YJTestLog clear];
    
    BOOL success = [YJHook swizzleClassMethod:@selector(hookClassMethod2)
                                          inClass:YJHookTestClass_B.class
                                   forceImplement:NO
                                    newImpFactory:^id(YJHookInfo *swizzleInfo) {
        return ^(__unsafe_unretained id SELF) {
            void (*originalIMP)(__unsafe_unretained id, SEL);
            originalIMP = (typeof(originalIMP))swizzleInfo.originalImplementation;
            [YJTestLog log:@"B'1"];
            originalIMP(SELF, swizzleInfo.selector);
            [YJTestLog log:@"B'2"];
        };
    }];
    XCTAssertTrue(success);
    
    [YJHookTestClass_B hookClassMethod2];
    XCTAssertTrue([YJTestLog is:@"B'1AB'2"]);
}

@end
