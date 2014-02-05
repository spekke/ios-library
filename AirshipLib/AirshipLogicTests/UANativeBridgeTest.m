
#import <XCTest/XCTest.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "UANativeBridge.h"
#import "UAWebViewCallData.h"

@interface UANativeBridgeTest : XCTestCase
@property(nonatomic, strong) JSContext *jsc;
@property(nonatomic, strong) NSString *nativeBridge;
@end

@implementation UANativeBridgeTest

- (void)setUp {
    [super setUp];

    self.nativeBridge = [NSString stringWithCString:(const char *)UANativeBridge_js encoding:NSUTF8StringEncoding];

    self.jsc = [[JSContext alloc] initWithVirtualMachine:[[JSVirtualMachine alloc] init]];

    //UAirship and window are only used for storage – the former is injected when setting up a UIWebView,
    //and the latter appears to be non-existant in JavaScriptCore
    [self.jsc evaluateScript:@"UAirship = {}"];
    [self.jsc evaluateScript:@"window = {}"];

    [self.jsc evaluateScript:self.nativeBridge];
}

- (void)tearDown {
    [super tearDown];
}

// Make sure that the functions defined in UANativeBridge.js are at least parsing
- (void)testNativeBridgeParsed {
    JSValue *value = [self.jsc evaluateScript:@"UAirship.delegateCallURL"];
    XCTAssertFalse([value.toString isEqualToString:@"undefined"], @"UAirship.runAction should not be undefined");
    value = [self.jsc evaluateScript:@"UAirship.invoke"];
    XCTAssertFalse([value.toString isEqualToString:@"undefined"], @"UAirship.invoke should not be undefined");
    value = [self.jsc evaluateScript:@"UAirship.runAction"];
    XCTAssertFalse([value.toString isEqualToString:@"undefined"], @"UAirship.runAction should not be undefined");
    value = [self.jsc evaluateScript:@"UAirship.finishAction"];
    XCTAssertFalse([value.toString isEqualToString:@"undefined"], @"UAirship.finishAction should not be undefined");
}

// UAirship.delegateCallURL is a pure function that builds JS delegate call URLs out of the passed arguments
- (void)testdelegateCallURL {
    JSValue *value = [self.jsc evaluateScript:@"UAirship.delegateCallURL('foo', 3)"];
    XCTAssertEqualObjects(value.toString, @"uairship://foo/3");
    value = [self.jsc evaluateScript:@"UAirship.delegateCallURL('foo', {'baz':'boz'})"];
    XCTAssertEqualObjects(value.toString, @"uairship://foo/?baz=boz");
    value = [self.jsc evaluateScript:@"UAirship.delegateCallURL('foo', 'bar', {'baz':'boz'})"];
    XCTAssertEqualObjects(value.toString, @"uairship://foo/bar?baz=boz");
}

// Test that UAirship.invoke attaches and removes an iframe from the DOM
// note: there appears to be no DOM in JavaScriptCore, but we can fake it for the purposes
// of this test
- (void)testInvoke {

    __block NSString *createdElement;
    __block NSDictionary *appendedChild;
    __block NSDictionary *removedChild;

    NSString *url = @"uaairship://foo/bar";

    //this will be the document.body object
    NSDictionary *body = @{@"appendChild":^(id child){
        XCTAssertNil(removedChild, @"child should not have been removed yet");
        appendedChild = child;
    }, @"removeChild":^(id child){
        XCTAssertNotNil(appendedChild, @"child should have first been appended");
        removedChild = child;
    }};

    //set the parent node of the generated child to the body
    NSDictionary *child = @{@"parentNode":body, @"style":@{}};

    //the child, by the time it is appended and removed, should have its src property set to the url
    //and its style should be set to display.none
    NSMutableDictionary *expectedChild = [child mutableCopy];
    [expectedChild setValue:url forKey:@"src"];
    [expectedChild setValue:@{@"display":@"none"} forKey:@"style"];

    //create the dummy document object
    self.jsc[@"document"] = @{@"createElement":^(NSString *element){
        createdElement = element;
        return child;
    }, @"body":body};

    [self.jsc evaluateScript:[NSString stringWithFormat:@"UAirship.invoke('%@')", url]];

    XCTAssertEqualObjects(createdElement, @"iframe", @"iframe should have been created");
    XCTAssertEqualObjects(appendedChild, expectedChild, @"child should have been appended");
    XCTAssertEqualObjects(removedChild, expectedChild, @"child should have been removed");
}

- (void)testRunAction {

    //set to YES if UAirship.invoke is called
    __block BOOL invoked = NO;
    //set to YES if the callback passed into UAirship.runAction executes
    __block BOOL finished = NO;
    //the result value passed through the runAction callback
    __block NSString *finishResult;

    __weak JSContext *weakContext = self.jsc;

    //mock UAirship.invoke that immediately calls UAirship.finishAction with a result string and the passed callback ID
    self.jsc[@"UAirship"][@"invoke"] = ^(NSString *url) {
        UAWebViewCallData *data = [UAWebViewCallData callDataForURL:[NSURL URLWithString:url]];
        NSString *cbID = [data.arguments firstObject];
        invoked = YES;
        NSString *callFinishAction = [NSString stringWithFormat:@"UAirship.finishAction(null,'\"done\"', '%@')",cbID];
        [weakContext evaluateScript:callFinishAction];
    };

    //function invoked by the runAction callback, for verification
    self.jsc[@"finishTest"] = ^(NSString *result){
        finished = YES;
        finishResult = result;
    };

    [self.jsc evaluateScript:@"\
        try { \
          UAirship.runAction('test_action', 'foo', function(err, result) { \
            finishTest(result)}) \
        } \
        catch(err) { \
          err \
        };"];

    XCTAssertTrue(invoked, @"UAirship.invoke should have been called");
    XCTAssertTrue(finished, @"finishTest should have been run in the action callback");
    XCTAssertEqualObjects(finishResult, @"done", @"result of finishTest should be 'done'");
}

@end