//
//  GPSocket.m
//  kqueue
//
//  Created by Dalton Cherry on 9/4/12.
//  Copyright (c) 2012 Lightspeed Systems. All rights reserved.
//

#import "GPSocket.h"

@implementation GPSocket

@synthesize hostname,portNumber,timeout,inUse,isConnected,keepAlive;
//////////////////////////////////////////////////////////////////////////////////////
//runs init with address.
-(id)init
{
    return [self initWithHostname:nil port:80];
}
//////////////////////////////////////////////////////////////////////////////////////
//Sets the default hostname
-(id)initWithHostname:(NSString *)host
{
    hostname = host;
    return [self initWithHostname:host port:80];
}
//////////////////////////////////////////////////////////////////////////////////////
//Sets up the default values.
-(id)initWithHostname:(NSString *)host port:(int)port
{
    self = [super init];
    
    if(self)
    {
        timeout = 5;
        sQueue = [[KQueue alloc] init];
        sQueue.hostname = host;
        sQueue.portNumber = port;
        sQueue.timeout = timeout;
        lock = [[NSLock alloc] init];
    }
    
    return self;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setTimeout:(int)time
{
    sQueue.timeout = time;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setPortNumber:(int)port
{
    sQueue.portNumber = port;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setHostname:(NSString *)name
{
    sQueue.hostname = name;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setIsSecureEnabled:(BOOL)isSecure
{
    sQueue.isSecureEnabled = isSecure;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)connect
{
    isConnected = [sQueue openConnection];
    if(keepAlive && isConnected)
        keepAliveTimer = [[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(keepAliveWrite) userInfo:nil repeats:YES] retain];
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)close
{
    isConnected = NO;
    [sQueue closeConnection];
    if(keepAlive)
        [keepAliveTimer invalidate];
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)writeString:(NSString*)string
{
    [self writeString:string useQueue:YES];
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)writeString:(NSString*)string useQueue:(BOOL)useQueue
{
    [lock lock];
    inUse = YES;
    if(!useQueue)
        [sQueue writeWithString:string];
    else
    {
        if(!writeQueue)
            writeQueue = [[NSMutableArray alloc] init];
        [writeQueue addObject:string];
        if(writeQueue.count == 1)
        {
            //NSLog(@"did write straight: %@",string);
            [sQueue writeWithString:string];
        }
        //[self dequeueWrite];//[sQueue writeWithString:string];
    }
    inUse = NO;
    [lock unlock];
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)writeData:(NSData*)data
{
    inUse = YES;
    [sQueue writeWithData:data];
    inUse = NO;
}
//////////////////////////////////////////////////////////////////////////////////////
-(NSString*)readString
{
    [lock lock];
    inUse = YES;
    NSString* response = [sQueue readString];
    inUse = NO;
    [lock unlock];
    return response;
}
//////////////////////////////////////////////////////////////////////////////////////
-(NSData*)readData
{
    [lock lock];
    inUse = YES;
    long bytes = 0;
    NSMutableData* response = [NSMutableData dataWithData:[sQueue readData:&bytes]];
    inUse = NO;
    [lock unlock];
    return response;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)dequeueWrite
{
    [lock lock];
    currentString = nil;
    int count = writeQueue.count;
    if(count > 0)
    {
        //NSString* old = [writeQueue objectAtIndex:0];
        //NSLog(@"did remove from queue: %@",old);
        currentString = [[writeQueue objectAtIndex:0] retain];
        [writeQueue removeObjectAtIndex:0];
        count--;
        if(count > 0)
        {
            NSString* next = [writeQueue objectAtIndex:0];
            //NSLog(@"did dequeue: %@",next);
            if(next)
                [sQueue writeWithString:next];
        }
    }
    [lock unlock];
}
//////////////////////////////////////////////////////////////////////////////////////
-(NSData*)readDataChunk:(int)len
{
    return [sQueue readChunk:len];
}
//////////////////////////////////////////////////////////////////////////////////////
-(NSString*)readStringChunk:(int)len
{
    NSData* data = [self readDataChunk:len];
    if(data)
    {
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return string;
    }
    return nil;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)keepAliveWrite
{
    if(!inUse)
        [self writeString:@" "];
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)rewrite
{
    if(currentString)
    {
        NSLog(@"rewrite string: %@",currentString);
        [sQueue writeWithString:currentString];
    }
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    [writeQueue release];
    [keepAliveTimer release];
    [sQueue release];
    [super dealloc];
}
//////////////////////////////////////////////////////////////////////////////////////

@end
