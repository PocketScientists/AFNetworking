//
// AFJSONPRequestOperation.m
//
// Created by Manfred Scheiner - http://scheinem.com on 10.11.12.
// Copyright (c) 2012 PocketScience - http://pocketscience.at
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFJSONPRequestOperation.h"

static dispatch_queue_t af_jsonp_request_operation_processing_queue;
static dispatch_queue_t jsonp_request_operation_processing_queue() {
    if (af_jsonp_request_operation_processing_queue == NULL) {
        af_jsonp_request_operation_processing_queue = dispatch_queue_create("com.alamofire.networking.jsonp-request.processing", 0);
    }
    
    return af_jsonp_request_operation_processing_queue;
}

@interface AFJSONPRequestOperation ()
@property (nonatomic, strong, readwrite) id responseJSON;
@property (nonatomic, strong, readwrite) NSString *callbackFunctionJSONP;
@property (nonatomic, strong, readwrite) NSError *JSONPError;
@end

@implementation AFJSONPRequestOperation

+ (AFJSONPRequestOperation *)JSONPRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                                      success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success 
                                                      failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    AFJSONPRequestOperation *requestOperation = [[self alloc] initWithRequest:urlRequest];
    requestOperation.callbackFunctionKey = @"AFJSONPCallbackFunction";
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) {
            success(operation.request, operation.response, responseObject);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(operation.request, operation.response, error, [(AFJSONPRequestOperation *)operation responseJSON]);
        }
    }];
    
    return requestOperation;
}

- (id)responseJSON {
    if (!_responseJSON && [self.responseData length] > 0 && [self isFinished] && !self.JSONPError) {
        NSError *error = nil;

        if ([self.responseData length] == 0) {
            _responseJSON = nil;
        } else {
            NSString *jsonpString = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
            NSString *jsonString = [[jsonpString substringToIndex:(jsonpString.length-1)] substringFromIndex:([jsonpString rangeOfString:@"{"].location + 1)];
            NSString *jsonStringWithCallbackFunction = [NSString stringWithFormat:@"{\"%@\":\"%@\",%@", self.callbackFunctionKey, self.callbackFunctionJSONP, jsonString];
            _responseJSON = [NSJSONSerialization JSONObjectWithData:[jsonStringWithCallbackFunction dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
        }
        
        self.JSONPError = error;
    }
    
    return _responseJSON;
}

- (NSString *)callbackFunctionJSONP {
    if (!_callbackFunctionJSONP && [self.responseData length] > 0 && [self isFinished] && !self.JSONPError) {
        if ([self.responseData length] == 0) {
            _callbackFunctionJSONP = nil;
        } else {
            NSString *jsonpString = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
           _callbackFunctionJSONP = [jsonpString substringToIndex:([jsonpString rangeOfString:@"("].location)];
        }
    }
    
    return _callbackFunctionJSONP;
}

- (NSError *)error {
    if (_JSONPError) {
        return _JSONPError;
    } else {
        return [super error];
    }
}

#pragma mark - AFHTTPRequestOperation

+ (NSSet *)acceptableContentTypes {
    return [NSSet setWithObjects:@"text/javascript", @"application/javascript", @"text/html", nil];
}

+ (BOOL)canProcessRequest:(NSURLRequest *)request {
    return [[[request URL] pathExtension] isEqualToString:@"jsonp"] || [super canProcessRequest:request];
}

- (void)setCompletionBlockWithSuccess:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                              failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
   self.completionBlock = ^ {
        if ([self isCancelled]) {
            return;
        }
        
        if (self.error) {
            if (failure) {
                dispatch_async(self.failureCallbackQueue ?: dispatch_get_main_queue(), ^{
                    failure(self, self.error);
                });
            }
        } else {
            dispatch_async(jsonp_request_operation_processing_queue(), ^{
                id JSON = self.responseJSON;
                
                if (self.JSONPError) {
                    if (failure) {
                        dispatch_async(self.failureCallbackQueue ?: dispatch_get_main_queue(), ^{
                            failure(self, self.error);
                        });
                    }
                } else {
                    if (success) {
                        dispatch_async(self.successCallbackQueue ?: dispatch_get_main_queue(), ^{
                            success(self, JSON);
                        });
                    }                    
                }
            });
        }
    };
#pragma clang diagnostic pop
}

@end
