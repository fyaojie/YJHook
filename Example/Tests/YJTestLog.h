//
//  YJTestLog.h
//  YJHook_Tests
//
//  Created by symbio on 2021/9/30.
//  Copyright © 2021 562925462@qq.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YJTestLog : NSObject

+ (void)log:(NSString *)string;
+ (void)clear;
+ (BOOL)is:(NSString *)compareString;
+ (NSString *)logString;

@end

NS_ASSUME_NONNULL_END
