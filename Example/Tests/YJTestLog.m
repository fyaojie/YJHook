//
//  YJTestLog.m
//  YJHook_Tests
//
//  Created by symbio on 2021/9/30.
//  Copyright © 2021 562925462@qq.com. All rights reserved.
//

#import "YJTestLog.h"
#import <XCTest/XCTest.h>

@implementation YJTestLog

static NSMutableString *_logString = nil;

+ (void)log:(NSString *)string {
    if (!_logString) {
        _logString = [NSMutableString new];
    }
    [_logString appendString:string];
    NSLog(@"%@", string);
}

+ (void)clear {
    _logString = [NSMutableString new];
}

+ (BOOL)is:(NSString *)compareString {
    return [_logString isEqualToString:compareString];
}

+ (NSString *)logString {
    return _logString;
}

@end

@interface YJTestLogTests : XCTestCase
@end

@implementation YJTestLogTests

- (void)setUp {
    [YJTestLog clear];
}

- (void)testLog {
    [YJTestLog log:@"AA"];
    [YJTestLog is:@"AA"];
    XCTAssertTrue([[YJTestLog logString] isEqualToString:@"AA"]);
    
    [YJTestLog log:@"BB"];
    [YJTestLog is:@"AABB"];
    XCTAssertTrue([[YJTestLog logString] isEqualToString:@"AABB"]);
    
    [YJTestLog clear];
    [YJTestLog is:@""];
    XCTAssertTrue([[YJTestLog logString] isEqualToString:@""]);
}

@end
