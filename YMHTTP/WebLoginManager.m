//
//  WebLoginManager.m
//  pixiv-client
//
//  Created by Zeyong Zhou on 2021/2/14.
//  Copyright © 2021 bravedefault. All rights reserved.
//

#import "WebLoginManager.h"
#import "curl.h"

@interface WebLoginManager (){
    CURL *_curl;
    NSData *_dataToSend;
    size_t _dataToSendBookmark;
    NSMutableData *_dataReceived;
}

@property(nonatomic, retain) NSHTTPCookieStorage* cookieStorage;
@property(nonatomic, retain) NSMutableDictionary *headerFields;
- (size_t) copyUpToThisManyBytes:(size_t)bytes intoThisPointer:(void *)pointer;
- (void) receivedData: (NSData *)data;
- (void) printDebugInformation: (NSString*) text;
- (void) receivedResponseHeaderData: (NSData*) data;
@end

// Function called by libcurl to deliver info/debug and payload data
int curl_debug_function(CURL *curl, curl_infotype infotype, char *info, size_t infoLen, void *contextInfo) {
    WebLoginManager *manager = (__bridge WebLoginManager *)contextInfo;
    NSData *infoData = [NSData dataWithBytes:info length:infoLen];
    NSString *infoStr = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
    if (infoStr) {
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];    // convert CR/LF to LF
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];    // convert CR to LF
        switch (infotype) {
            case CURLINFO_DATA_IN:
                [manager printDebugInformation:infoStr];
                break;
            case CURLINFO_DATA_OUT:
                [manager printDebugInformation:[infoStr stringByAppendingString:@"\n"]];
                break;
            case CURLINFO_HEADER_IN:
                [manager printDebugInformation:[@"<<" stringByAppendingString:infoStr]];
                break;
            case CURLINFO_HEADER_OUT:
                infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\n" withString:@"\n>> "];
                [manager printDebugInformation:[NSString stringWithFormat:@">> %@\n", infoStr]];
                break;
            case CURLINFO_TEXT:
                [manager printDebugInformation:[@"-- " stringByAppendingString:infoStr]];
                break;
            default:    // ignore the other CURLINFOs
                break;
        }
    }
    return 0;
}

NS_INLINE WebLoginManager *from(void *userdata) {
    if (!userdata) return nil;
    return (__bridge WebLoginManager *)userdata;
}

// Function called by libcurl to update progress
int curl_progress_function(void *clientp, double dltotal, double dlnow, double ultotal, double ulnow) {
    // Placeholder - add progress bar?
    // NSLog(@"iOSCurlProgressCallback %f of %f", dlnow, dltotal);
    return 0;
}

// Function called by libcurl to deliver packets from web response
size_t curl_write_function(char *ptr, size_t size, size_t nmemb, void *userdata) {
    const size_t sizeInBytes = size*nmemb;
    WebLoginManager *manager = (__bridge WebLoginManager *)userdata;
    NSData *data = [[NSData alloc] initWithBytes:ptr length:sizeInBytes];
    [manager receivedData:data];  // send to WebLoginManager
    return sizeInBytes;
}

size_t curl_header_function(char *data, size_t size, size_t nmemb, void *userdata) {
    const size_t sizeInBytes = size*nmemb;
    WebLoginManager *handle = from(userdata);
    NSData *buffer = [[NSData alloc] initWithBytes:data length:size * nmemb];
    [handle receivedResponseHeaderData:buffer];
    return sizeInBytes;
}

// Function called by libcurl to get data for uploads to web server
size_t curl_read_function(void *ptr, size_t size, size_t nmemb, void *userdata) {
    const size_t sizeInBytes = size*nmemb;
    WebLoginManager *manager = (__bridge WebLoginManager *)userdata;
    return [manager copyUpToThisManyBytes:sizeInBytes intoThisPointer:ptr];
}

@implementation WebLoginManager

- (instancetype) init {
    self = [super init];
    if (self) {
        _dataReceived = [[NSMutableData alloc] init];
        _curl = curl_easy_init();
        _cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    }
    return self;
}

- (void) startRequest: (NSURLRequest*) request originalUrl:(NSURL*) url host:(NSString*) host{
    self.originalUrl = url;
    self.requestHost = self.originalUrl.host;
    self.requestUrl = request.URL;
    self.request = [self setCookiesOnReqeust:request];
    self.request = [self bindRequestHost:self.request];
    [self startRequest];
}

- (void) startRequest {
    _headerFields = [NSMutableDictionary dictionary];
    NSURL* url = self.requestUrl;
    CURLcode result;
    [_dataReceived setLength:0U];
    // Set CURL callback functions
//    curl_easy_setopt(_curl, CURLOPT_DEBUGFUNCTION, curl_debug_function);  // function to get debug data to view
//    curl_easy_setopt(_curl, CURLOPT_DEBUGDATA, self);
    curl_easy_setopt(_curl, CURLOPT_WRITEDATA, self);    // prevent libcurl from writing the data to stdout
    curl_easy_setopt(_curl, CURLOPT_WRITEFUNCTION, curl_write_function);  // function to get write data to view
    curl_easy_setopt(_curl, CURLOPT_READDATA, self);
    curl_easy_setopt(_curl, CURLOPT_READFUNCTION, curl_read_function);
    curl_easy_setopt(_curl, CURLOPT_HEADERDATA, self);
    curl_easy_setopt(_curl, CURLOPT_HEADERFUNCTION, curl_header_function);
    curl_easy_setopt(_curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(_curl, CURLOPT_PROGRESSFUNCTION, curl_progress_function);
    curl_easy_setopt(_curl, CURLOPT_PROGRESSDATA, self);  // libcurl will pass back dl data progress
    
    // Set some CURL options
    curl_easy_setopt(_curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);    // user/pass may be in URL
    curl_easy_setopt(_curl, CURLOPT_USERAGENT, curl_version());    // set a default user agent
    curl_easy_setopt(_curl, CURLOPT_VERBOSE, 1L);    // turn on verbose
    curl_easy_setopt(_curl, CURLOPT_TIMEOUT, 60L); // seconds
    curl_easy_setopt(_curl, CURLOPT_MAXCONNECTS, 0L); // this should disallow connection sharing
    curl_easy_setopt(_curl, CURLOPT_FORBID_REUSE, 1L); // enforce connection to be closed
    curl_easy_setopt(_curl, CURLOPT_DNS_CACHE_TIMEOUT, 0L); // Disable DNS cache
    curl_easy_setopt(_curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0); // enable HTTP2 Protocol
    curl_easy_setopt(_curl, CURLOPT_SSLVERSION, CURL_SSLVERSION_DEFAULT); // Force TLSv1 protocol - Default
    curl_easy_setopt(_curl, CURLOPT_SSL_CIPHER_LIST, [@"ALL" UTF8String]);
    curl_easy_setopt(_curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(_curl, CURLOPT_SSL_VERIFYHOST, 0L);   // 1L to verify, 0L to disable
    curl_easy_setopt(_curl, CURLOPT_UPLOAD, 0L);
    
    struct curl_slist* headerList = [self addHeaders:self.request.allHTTPHeaderFields];
    curl_easy_setopt(_curl, CURLOPT_HTTPHEADER, headerList); // no headers sent
//    curl_easy_setopt(_curl, CURLOPT_COOKIE)
    curl_easy_setopt(_curl, CURLOPT_CUSTOMREQUEST,nil);
    if (![self.request.HTTPMethod isEqualToString:@"GET"]) {
        curl_easy_setopt(_curl, CURLOPT_CUSTOMREQUEST, self.request.HTTPMethod.UTF8String);
        NSString *body = [[NSString alloc] initWithData:self.request.HTTPBody encoding:NSUTF8StringEncoding];
        NSLog(@"body:%@", body);
        curl_easy_setopt(_curl, CURLOPT_POSTFIELDS, [body UTF8String]);
    }else {
        curl_easy_setopt(_curl, CURLOPT_HTTPGET, 1L); // use HTTP GET method
    }
    
    curl_easy_setopt(_curl, CURLOPT_URL, [url.absoluteString UTF8String]);
    
    // PERFORM the Curl
    result = curl_easy_perform(_curl);
    if (result == CURLE_OK) {
        long http_code, http_ver;
        double total_time, total_size, total_speed, timing_ns, timing_tcp, timing_ssl, timing_fb;
        char *redirect_url2 = NULL;
        curl_easy_getinfo(_curl, CURLINFO_RESPONSE_CODE, &http_code);
        curl_easy_getinfo(_curl, CURLINFO_TOTAL_TIME, &total_time);
        curl_easy_getinfo(_curl, CURLINFO_SIZE_DOWNLOAD, &total_size);
        curl_easy_getinfo(_curl, CURLINFO_SPEED_DOWNLOAD, &total_speed); // total
        curl_easy_getinfo(_curl, CURLINFO_APPCONNECT_TIME, &timing_ssl); // ssl handshake time
        curl_easy_getinfo(_curl, CURLINFO_CONNECT_TIME, &timing_tcp); // tcp connect
        curl_easy_getinfo(_curl, CURLINFO_NAMELOOKUP_TIME, &timing_ns); // name server lookup
        curl_easy_getinfo(_curl, CURLINFO_STARTTRANSFER_TIME, &timing_fb); // firstbyte
        curl_easy_getinfo(_curl, CURLINFO_REDIRECT_URL, &redirect_url2); // redirect URL
        curl_easy_getinfo(_curl, CURLINFO_HTTP_VERSION, &http_ver); // HTTP protocol
        
        NSString *http_ver_s, *http_h=@"";
        if(http_ver == CURL_HTTP_VERSION_1_0) {
            http_ver_s = @"HTTP/1.0";
            http_h = @"HTTP/1.0";
        }
        if(http_ver == CURL_HTTP_VERSION_1_1) {
            http_ver_s = @"HTTP/1.1";
            http_h = @"HTTP/1.1";
        }
        if(http_ver == CURL_HTTP_VERSION_2_0) {
            http_ver_s = @"HTTP/2";
            http_h = @"HTTP/2";
        }
        self.response = [[NSHTTPURLResponse alloc] initWithURL:self.originalUrl statusCode:http_code HTTPVersion:http_ver_s headerFields:self.headerFields];
        
        if (http_code == 301 || http_code == 302) {
            NSString* redirectUrl = [NSString stringWithCString:redirect_url2 encoding:NSUTF8StringEncoding];
            [self printDebugInformation:redirectUrl];
            
            NSURL *url = [NSURL URLWithString:redirectUrl];
            NSMutableURLRequest* modifiedRequest = [NSMutableURLRequest requestWithURL:url];
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(LoginManager:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
                [self.delegate LoginManager:self willPerformHTTPRedirection:self.response newRequest:modifiedRequest completionHandler:^(NSURLRequest * _Nullable request, NSURL * _Nullable originalUrl, NSString *_Nullable host) {
                    [self startRequest:request originalUrl:originalUrl host:host];
                }];
            }else {
                [self startRequest:modifiedRequest originalUrl:url host:url.host];
            }
        }else {
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(LoginManager:didReceiveResponse:receivedData:)]) {
                [self.delegate LoginManager:self didReceiveResponse:self.response receivedData:_dataReceived];
            }
        }
    }else {
        NSString *errorCode = [NSString stringWithFormat:@"\n** TRANSFER INTERRUPTED - ERROR [%d]\n", result];
        [self printDebugInformation:errorCode];
    }
}

- (NSURLRequest *)setCookiesOnReqeust:(NSURLRequest *)request {
    NSMutableURLRequest *r = [request mutableCopy];
    if (self.cookieStorage && request.URL) {
        NSString *urlString = [NSString stringWithFormat:@"https://%@", self.requestHost];
        NSURL* url = [NSURL URLWithString:urlString];
        NSArray *cookies = [_cookieStorage cookiesForURL:url];
        if (cookies && cookies.count) {
            NSDictionary *cookiesHeaderFields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
            NSString *cookieValue = cookiesHeaderFields[@"Cookie"];
            if (cookieValue && cookieValue.length) {
                [r setValue:cookieValue forHTTPHeaderField:@"Cookie"];
            }
        }
    }
    return [r copy];
}

-(NSURLRequest *) bindRequestHost:(NSURLRequest *)request {
   NSMutableURLRequest *r = [request mutableCopy];
    [r setValue:self.requestHost forHTTPHeaderField:@"Host"];
   return [r copy];
}

- (struct curl_slist*) addHeaders:(NSDictionary*) headers {
    struct curl_slist *_headerList = NULL;
    for (NSString* key in headers.allKeys) {
        NSString* value = [headers objectForKey:key];
        NSString* header = [NSString stringWithFormat:@"%@: %@", key, value];
        _headerList = curl_slist_append(_headerList, [header UTF8String]);
    }
    return _headerList;
}

- (size_t)copyUpToThisManyBytes:(size_t)bytes intoThisPointer:(void *)pointer {
    size_t bytesToGo = _dataToSend.length-_dataToSendBookmark;
    size_t bytesToGet = MIN(bytes, bytesToGo);
    if (bytesToGo) {
        [_dataToSend getBytes:pointer range:NSMakeRange(_dataToSendBookmark, bytesToGet)];
        _dataToSendBookmark += bytesToGet;
        return bytesToGet;
    }
    return 0U;
}

- (void)receivedData:(NSData *)data {
    [_dataReceived appendData:data];
}

- (void) printDebugInformation:(NSString *)text {
    NSLog(@"%@", text);
}

- (void) receivedResponseHeaderData: (NSData*) data {
    [self setCookiesWithHeaderData:data];
}

- (void)setCookiesWithHeaderData:(NSData *)data {
    NSString *headerLine = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (headerLine.length == 0) return;

    NSRange r = [headerLine rangeOfString:@":"];
    if (r.location != NSNotFound) {
        NSString *head = [headerLine substringToIndex:r.location];
        NSString *tail = [headerLine substringFromIndex:r.location + 1];

        NSCharacterSet *set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *key = [head stringByTrimmingCharactersInSet:set];
        NSString *value = [tail stringByTrimmingCharactersInSet:set];

        if (key && value) {
            if (!_headerFields) _headerFields = [NSMutableDictionary dictionary];
            if (_headerFields[key]) {
                NSString *v = [NSString stringWithFormat:@"%@, %@", _headerFields[key], value];
                [_headerFields setObject:v forKey:key];
            } else {
                _headerFields[key] = value;
            }
            if ([key isEqualToString:@"set-cookie"]) {
                NSString *urlString = [NSString stringWithFormat:@"https://%@", self.requestHost];
                NSURL* url = [NSURL URLWithString:urlString];
                NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie" : value} forURL:self.originalUrl];
                if ([cookies count] == 0) return;
                [self.cookieStorage setCookies:cookies forURL:url mainDocumentURL:nil];
            }
            
        }
    }
}

@end
