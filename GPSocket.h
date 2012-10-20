//
//  GPSocket.h
//  kqueue
//
//  Created by Dalton Cherry on 9/4/12.
//  Copyright (c) 2012 Lightspeed Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KQueue.h"

@interface GPSocket : NSObject
{
    KQueue* sQueue;
    NSTimer* keepAliveTimer;
    NSMutableArray* writeQueue;
    NSLock *lock;
    NSString* currentString;
}

@property(nonatomic,strong)NSString *hostname;
@property(nonatomic) int portNumber;
@property(nonatomic) int timeout;
@property(nonatomic) BOOL isSecureEnabled;
@property(nonatomic) BOOL keepAlive;
@property(nonatomic) BOOL inUse;
@property(nonatomic,readonly) BOOL isConnected;

-(id)initWithHostname:(NSString *)host;
-(id)initWithHostname:(NSString *)host port:(int)port;

-(void)connect;
-(void)close;
-(void)writeString:(NSString*)string;
-(void)writeString:(NSString*)string useQueue:(BOOL)useQueue;
-(void)writeData:(NSData*)data;
-(NSString*)readString;
-(NSData*)readData;

-(void)dequeueWrite;

-(void)rewrite;

-(NSData*)readDataChunk:(int)len;
-(NSString*)readStringChunk:(int)len;

@end
