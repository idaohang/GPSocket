///////////////////////////////////////////////////////////////////////////
//
//  KQueue.h
//  kqueue
//
//  Created by Austin Cherry on 8/9/12.
//  Copyright (c) 2012 Lightspeed Systems. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////

#import <Foundation/Foundation.h>

#ifndef KQUEUE_SSL
#define KQUEUE_SSL 1
#define KQUEUE_SSL_ENABLE
#endif

@interface KQueue : NSObject
{
    BOOL isSecureEnabled;
    int sckfd;
    BOOL didSSLConnect;
    
}

@property(nonatomic,strong)NSString *hostname;
@property(nonatomic) int portNumber;
@property(nonatomic) int timeout;
@property(nonatomic) BOOL isSecureEnabled;
@property(nonatomic) long bytes;

-(id)initWithHostname:(NSString *)host;
-(id)initWithAddress:(NSString *)host port:(int)port;

-(BOOL)openConnection;
-(BOOL)listenConnection;
-(void)closeConnection;
-(NSData *)readData;
-(NSString *)readString;
-(NSString *)readString:(long*)bytes;
-(NSData*)readData:(long*)bytes;
-(BOOL)writeWithData:(NSData *)data;
-(BOOL)writeWithString:(NSString *)string;
- (NSString *)getIPAddress;
-(BOOL)validateIP:(NSString *)serverName;

-(NSData*)readChunk:(int)len;

@end
