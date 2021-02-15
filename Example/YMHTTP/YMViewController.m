//
//  YMViewController.m
//  YMHTTP
//
//  Created by zymxxxs on 12/31/2019.
//  Copyright (c) 2019 zymxxxs. All rights reserved.
//

#import "YMViewController.h"
#import <YMHTTP/YMHTTP.h>

@interface YMViewController ()<YMURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *us;
@property (nonatomic, strong) YMURLSession *yus;


@end

@implementation YMViewController

- (void)viewDidLoad{
    [super viewDidLoad];
    ////https://app-api.pixiv.net/web/v1/login?code_challenge=M4_JWzwE25zio6wx9bvxC7vX9ObTEdLlZWPFI1Rdwl8&code_challenge_method=S256&client=pixiv-android
    NSURL* url = [[NSURL alloc] initWithString:@"https://210.140.131.222/web/v1/login?code_challenge=M4_JWzwE25zio6wx9bvxC7vX9ObTEdLlZWPFI1Rdwl8&code_challenge_method=S256&client=pixiv-android"];
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"app-api.pixiv.net" forHTTPHeaderField:@"Host"];
    YMURLSession* session = [YMURLSession sessionWithConfiguration:[YMURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
//    YMURLSessionTask* task = [session taskWithRequest:request];
    YMURLSessionTask* task = [session taskWithRequest:request completionHandler:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString* result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"%@", result);
    }];
    [task resume];
}

- (void)YMURLSession:(YMURLSession *)session
                          task:(YMURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
   completionHandler:(void (^)(NSURLRequest *_Nullable))completionHandler {
    NSString* location = [[response allHeaderFields] valueForKey:@"Location"];
    NSLog(@"%@", location);
}

- (void)YMURLSession:(YMURLSession *)session
                  task:(YMURLSessionTask *)task
    didReceiveResponse:(NSHTTPURLResponse *)response
   completionHandler:(void (^)(YMURLSessionResponseDisposition disposition))completionHandler {
    
}

- (void)YMURLSession:(YMURLSession *)session task:(YMURLSessionTask *)task didReceiveData:(NSData *)data {
    NSString* result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"%@", result);
}
@end
