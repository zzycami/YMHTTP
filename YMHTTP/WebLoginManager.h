//
//  WebLoginManager.h
//  pixiv-client
//
//  Created by Zeyong Zhou on 2021/2/14.
//  Copyright © 2021 bravedefault. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef WebLoginManager_h
#define WebLoginManager_h

@class WebLoginManager;

@protocol WebLoginManagerDelegate <NSObject>
@optional
- (void)LoginManager:(WebLoginManager * _Nonnull)manager
    willPerformHTTPRedirection:(NSHTTPURLResponse * _Nonnull)response
                    newRequest:(NSURLRequest * _Nonnull)request
             completionHandler:(void (^)(NSURLRequest *_Nullable, NSURL *_Nullable, NSString *_Nullable))completionHandler;
- (void)LoginManager:(WebLoginManager * _Nonnull)manager didReceiveResponse:(NSHTTPURLResponse *_Nonnull)response receivedData:(NSData *_Nonnull)data;
@end

@interface WebLoginManager : NSObject
// https://app-api.pixiv.net/web/v1/login?code_challenge=M4_JWzwE25zio6wx9bvxC7vX9ObTEdLlZWPFI1Rdwl8&code_challenge_method=S256&client=pixiv-android
@property(atomic, retain) NSURL* _Nullable originalUrl;
//@"https://210.140.131.222/web/v1/login?code_challenge=M4_JWzwE25zio6wx9bvxC7vX9ObTEdLlZWPFI1Rdwl8&code_challenge_method=S256&client=pixiv-android";
@property(atomic, retain) NSURL* _Nullable requestUrl;
//app-api.pixiv.net
@property(atomic, retain) NSString* _Nullable requestHost;
@property(atomic, retain) NSURLRequest* _Nullable request;
@property(atomic, retain) NSHTTPURLResponse* _Nullable response;
@property(atomic, retain, nullable) id<WebLoginManagerDelegate> delegate;

- (void) startRequest;
- (void) startRequest: (NSURLRequest* _Nonnull) request originalUrl:(NSURL* _Nullable) url host:(NSString* _Nullable) host;
@end

#endif /* WebLoginManager_h */
