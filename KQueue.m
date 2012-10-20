///////////////////////////////////////////////////////////////////////////
//
//  KQueue.m
//  kqueue
//
//  Created by Austin Cherry on 8/9/12.
//  Copyright (c) 2012 Lightspeed Systems. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////

#pragma GCC diagnostic ignored "-Wdeprecated-declarations" //for openssl warnings

#import "KQueue.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h> 
#include <sys/socket.h>
#include <netdb.h> 
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <ctype.h>
#include <errno.h>
#include <sys/fcntl.h>
#include <netinet/in.h>
#include <sys/event.h>
#include <sys/time.h>

#ifdef KQUEUE_SSL_ENABLE
#include "openssl/rand.h"
#include "openssl/ssl.h"
#include "openssl/err.h"

#import <Security/Security.h>

typedef struct {
    SSL *sslHandle;
    SSL_CTX *sslContext;
} SSLConnection;

SSLConnection *SSLconnect;

#endif

#define DEFAULT_BUFFER 1024 //4096

@interface KQueue ()

-(BOOL)streams:(NSData **)data isRead:(BOOL)isRead bytes:(long*)b;
-(void)sendDataToSocketFD:(const char *)buf len:(long)len;
-(BOOL)openSSLConnection;
-(void)closeSSLConnection;
-(BOOL)sslWriteStream:(const char *)buf length:(long)len;
-(int)sslReadStream:(char *)buf length:(long)len;

@end

@implementation KQueue

@synthesize hostname,portNumber,timeout, bytes,isSecureEnabled = isSecureEnabled;
//////////////////////////////////////////////////////////////////////////////////////
//runs init with address.
-(id)init
{
   return [self initWithAddress:nil port:80];
}
//////////////////////////////////////////////////////////////////////////////////////
//Sets the default hostname
-(id)initWithHostname:(NSString *)host
{
    hostname = host;
    return [self initWithAddress:host port:80];
}
//////////////////////////////////////////////////////////////////////////////////////
//Sets up the default values.
-(id)initWithAddress:(NSString *)host port:(int)port
{
    self = [super init];
    
    if(self)
    {
        hostname = host;
        portNumber = port;
        
        if(port == 443 && KQUEUE_SSL == 1)
            isSecureEnabled = YES;
        else
            isSecureEnabled = NO;
        
        timeout = 5;
    }
    
    return self;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setPortNumber:(int)port
{
    portNumber = port;
    if(port == 443 && KQUEUE_SSL == 1)
        isSecureEnabled = YES;
    else
        isSecureEnabled = NO;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)setIsSecureEnabled:(BOOL)isSecure
{
    isSecureEnabled = isSecure;
    if(!didSSLConnect)
    {
        didSSLConnect = YES;
        [self openSSLConnection];
    }
}
//////////////////////////////////////////////////////////////////////////////////////
//Opens the socket connection.
-(BOOL)openConnection
{
    if(!(hostname && portNumber))
        return NO;
    struct sockaddr_in server;
	struct hostent *hp;
    if( (hp = gethostbyname(hostname.UTF8String)) == NULL)
       return NO;
    
    if( (sckfd = socket(AF_INET, SOCK_STREAM, 0)) < 0)
		return NO;
    
    server.sin_family = AF_INET;
	server.sin_port = htons(portNumber);
	server.sin_addr = *((struct in_addr *)hp->h_addr);
	memset(&(server.sin_zero), 0, 8);
    
	fcntl(sckfd, F_SETFL, O_NONBLOCK);
	connect(sckfd, (struct sockaddr *)&server, sizeof(struct sockaddr));
    
    if(isSecureEnabled)
    {
        if(![self openSSLConnection])
            return NO;
        didSSLConnect = YES;
    }
    
    return YES;
}
//////////////////////////////////////////////////////////////////////////////////////
//Not sure on what we are going to do with this will come back to it.
-(BOOL)listenConnection
{
    return NO;
}
//////////////////////////////////////////////////////////////////////////////////////
//Closes the socket connection.
-(void)closeConnection
{
    if(isSecureEnabled)
        [self closeSSLConnection];
    shutdown(sckfd,SHUT_RDWR);
    close(sckfd);
}
//////////////////////////////////////////////////////////////////////////////////////
-(BOOL)writeWithData:(NSData *)data
{
    long b = 0;
    if([self streams:&data isRead:NO bytes:&b])
        return YES;
    
    return NO;
}
//////////////////////////////////////////////////////////////////////////////////////
-(BOOL)writeWithString:(NSString *)string
{
    NSData* data = [string dataUsingEncoding:[NSString defaultCStringEncoding]];
    return [self writeWithData:data];
}
//////////////////////////////////////////////////////////////////////////////////////
//Reads a string out of the stream.
-(NSData*)readData:(long*)b
{
    NSData *data = nil;
    if([self streams:&data isRead:YES bytes:b])
        return data;
    
    return nil;
}
//////////////////////////////////////////////////////////////////////////////////////
//Read data out of the stream.
-(NSData *)readData
{
    long b = 0;
    return [self readData:&b];
}
//////////////////////////////////////////////////////////////////////////////////////
//Reads a string out of the stream.
-(NSString *)readString
{
    long b = 0;
    return [self readString:&b];
}
//////////////////////////////////////////////////////////////////////////////////////
//Reads a string out of the stream.
-(NSString *)readString:(long*)b
{
    NSData* data = [self readData:b];
    if(data)
    {
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return string;
    }
    return nil;
}
//////////////////////////////////////////////////////////////////////////////////////
//This is really where all the magic happens.
//This method is the one that controls the read/write streams for kqueue.
// See this article for a quick overview of the kqueue and kevent structs.
//http://wiki.netbsd.org/tutorials/kqueue_tutorial/#index7h2
-(BOOL)streams:(NSData **)data isRead:(BOOL)isRead bytes:(long*)b
{
    //Setup our variables
    struct kevent changes; //events we are going to monitor
	struct kevent eventlist; //events that were triggered
	//char buf[DEFAULT_BUFFER] = {0};
	int kq, nev;
    
    //long dataBytes = 0;
    
	//get our kqueue descriptor
	kq = kqueue();
	if (kq == -1)
		return NO;
    
    //Set if we are going to be reading or writing to the stream
	if(isRead)
        EV_SET(&changes, sckfd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
	else
        EV_SET(&changes, sckfd, EVFILT_WRITE, EV_ADD | EV_CLEAR, 0, 0, NULL);
    
    //Set a timeout value.
    if(timeout == 0)
        nev = kevent(kq, &changes, 1, &eventlist, 1, NULL);
    else
    {
        struct timespec tm = { timeout,0 };
        nev = kevent(kq, &changes, 1, &eventlist, 1, &tm);
    }
	if (nev <= 0)
	{
        //NSLog(@"timeout");
		close(kq);
		return NO;
	}
    
	for(int i = 0; i < nev; i++)
	{
        //if kqueue gets an error.
		if(eventlist.flags & EV_ERROR)
		{
			close(kq);
			return NO;
		}
        
		//if in the write checking we need to test for EV_EOF first.
		if(!isRead && (eventlist.flags & EV_EOF || changes.flags & EV_EOF ) )
		{
			// read direction of socket has shutdown
            close(kq);
            return YES;
		}
        
        //This is where we actually read/write the stream.
		if(eventlist.ident == sckfd)
		{
            if(isRead)
            {
                long len = eventlist.data;
                NSData* chunk = [self readChunk:len];
                *data = chunk;
                //if the bytes we are reading equal 0 close the socket.
                *b = bytes;
                if(bytes <= 0)
                {
                    close(kq);
                    return YES;
                }
            }
            else
            {
            //Our write action.
                if(isSecureEnabled)
                    [self sslWriteStream:(char*)[*data bytes] length:[*data length]];
                else
                   [self sendDataToSocketFD:(char*)[*data bytes] len:[*data length]];
            }
		}
        
		//if we are reading check for this last.
        if(isRead && (eventlist.flags & EV_EOF || changes.flags & EV_EOF ))
		{
            // read direction of socket has shutdown
            close(kq);
            return YES;
		}
        
	}
	close(kq);
	return YES;
}
//////////////////////////////////////////////////////////////////////////////////////
-(NSData*)readChunk:(int)len
{
    NSData* data = nil;
    int cb = 0;
    char* buf = (char*)malloc(sizeof(char)*len);
    memset(buf, 0, len);
    if(isSecureEnabled)
        cb = [self sslReadStream:buf length:len];
    else
        cb = recv(sckfd, buf,len,0);
    if(cb > 0)
        data = [[[NSData alloc] initWithBytes:buf length:cb] autorelease];
    bytes = cb;
    free(buf);
    return data;
}
//////////////////////////////////////////////////////////////////////////////////////
//helper method for streams.
//this sends data to the socket discriptor. simple loop to send the data.
-(void)sendDataToSocketFD:(const char *)buf len:(long)len
{
	long bytessent, pos;
	pos = 0;
	do {
		if ((bytessent = send(sckfd, buf + pos, len - pos, 0)) < 0)
			return;
		pos += bytessent;
	} while (bytessent > 0);
}
//////////////////////////////////////////////////////////////////////////////////////
//IP helper routines.
//////////////////////////////////////////////////////////////////////////////////////
//Gets the IP address.
- (NSString *)getIPAddress 
{
    
    NSString *address = @"";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) 
    {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) 
        {
            if(temp_addr->ifa_addr->sa_family == AF_INET) 
            {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"])
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
    
}
//////////////////////////////////////////////////////////////////////////////////////
//Make sure it is a valid IP. Only does IP v4 addresses
-(BOOL)validateIP:(NSString *)serverName
{ 
	char *validater = malloc(sizeof(char[strlen(serverName.UTF8String)+1]));
	strcpy(validater,serverName.UTF8String);
    
	for(int i = 0; i < 4; i++)
	{
		int block = atoi(validater);
		if(255 < block || block < 0)
		{
			free(validater);
			return NO;
		}
		validater = strchr(validater, '.')+1;
	}
	free(validater);
	return YES;
}
//////////////////////////////////////////////////////////////////////////////////////
//SSL functions
//////////////////////////////////////////////////////////////////////////////////////
//Open SSL connection
-(BOOL)openSSLConnection
{
    // Register the error strings for libcrypto & libssl
    SSL_load_error_strings();
    // Register the available ciphers and digests
    SSL_library_init ();
    SSLconnect = (SSLConnection*)malloc(sizeof (SSLconnect));
    SSLconnect->sslHandle = NULL;
    SSLconnect->sslContext = NULL;
    
    if (sckfd)
    {
        // New context saying we are a client, and using SSL 2 or 3
        SSLconnect->sslContext = SSL_CTX_new (SSLv23_method() );
        if (SSLconnect->sslContext == NULL)
            ERR_print_errors_fp (stderr);
        
        SSL_CTX_set_verify(SSLconnect->sslContext,SSL_VERIFY_NONE,NULL);
        // Create an SSL struct for the connection
        SSLconnect->sslHandle = SSL_new (SSLconnect->sslContext);
        
        if (SSLconnect->sslHandle == NULL)
        {
            ERR_print_errors_fp (stderr);
            return NO;
        }
        
        // Connect the SSL struct to our connection
        if (!SSL_set_fd (SSLconnect->sslHandle, sckfd))
            ERR_print_errors_fp (stderr);
        
        ERR_clear_error();
        // Initiate SSL handshake
        if (SSL_connect(SSLconnect->sslHandle) != 1)
        {
            ERR_print_errors_fp (stderr);
           // ERR_clear_error();
           // int err = SSL_get_error(SSLconnect->sslHandle, 0);
           // NSLog(@"error code: %d",err);
        }
        return YES;
    }
    else
        perror ("Connect failed");
    return NO;
}
//////////////////////////////////////////////////////////////////////////////////////
//close the SSL Connection
-(void)closeSSLConnection
{
    if(SSLconnect)
    {
        if (SSLconnect->sslHandle)
        {
            SSL_shutdown (SSLconnect->sslHandle);
            SSL_free (SSLconnect->sslHandle);
        }
        if (SSLconnect->sslContext)
            SSL_CTX_free (SSLconnect->sslContext);
        free (SSLconnect);
    }
}
//////////////////////////////////////////////////////////////////////////////////////
//write SSL stream
-(BOOL)sslWriteStream:(const char *)buf length:(long)len
{
    int b = 0;
    int err = 0;
    do
    {
        ERR_clear_error();
        b = SSL_write(SSLconnect->sslHandle,buf,(int)len);
        err = SSL_get_error(SSLconnect->sslHandle, 0);
        if(err == SSL_ERROR_SSL && b < 0)
            return NO;
    } while (b < len);
    
    return YES;
}
//////////////////////////////////////////////////////////////////////////////////////
//read ssl stream
-(int)sslReadStream:(char *)buf length:(long)len
{
    int b = 0;
    int err = 0;
    do
    {
        ERR_clear_error();
        b = SSL_read(SSLconnect->sslHandle,buf,(int)len);
        err = SSL_get_error(SSLconnect->sslHandle, 0);
        if(b >= 0 || err == SSL_ERROR_ZERO_RETURN)
            break;
        else if(err == SSL_ERROR_SSL && b < 0)
            return NO;
        else if(err == SSL_ERROR_SYSCALL && b < 0)
            return NO;
    } while (true);
    
    return b;
}
//////////////////////////////////////////////////////////////////////////////////////
-(void)dealloc
{
    [hostname release];
    [super dealloc];
}
@end
