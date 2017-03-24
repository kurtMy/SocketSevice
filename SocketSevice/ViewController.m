//
//  ViewController.m
//  SocketSevice
//
//  Created by my on 2017/3/23.
//  Copyright © 2017年 my. All rights reserved.
//

#import "ViewController.h"
#import <CoreFoundation/CoreFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *portText;
@property (nonatomic, assign) NSInteger kPORT;
@property (weak, nonatomic) IBOutlet UITextField *putText;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (IBAction)startService:(id)sender {
    //设置服务端端口号
    self.kPORT = [self.portText.text integerValue];
    
    CFSocketRef service;
    /*CFSocketContext 参数cgindex version 版本号，必须为0；
     *void *info; 一个指向任意程序定义数据的指针，可以在CFScocket对象刚创建的时候与之关联，被传递给所有在上下文中回调,可为NULL；
     *CFAllocatorRetainCallBack retain; info指针中的retain回调，可以为NULL
     *CFAllocatorReleaseCallBack release; info指针中的release的回调，可以为NULL
     *CFAllocatorCopyDescriptionCallBack copyDescription; info指针中的回调描述，可以为NULL
     */
    CFSocketContext CTX = {0,NULL,NULL,NULL,NULL};
    //CFSockerRef
    //内存分配类型，一般为默认的Allocator->kCFAllocatorDefault,
    //协议族,一般为Ipv4:PF_INET,(Ipv6,PF_INET6),
    //套接字类型，TCP用流式—>SOCK_STREAM，UDP用报文式->SOCK_DGRAM,
    //套接字协议，如果之前用的是流式套接字类型：IPROTO_TCP，如果是报文式：IPPROTO_UDP,
    //回调事件触发类型 *1,
    //触发时候调用的方法 *2,
    //用户定义的数据指针，用于对CFSocket对象的额外定义或者申明，可以为NULL
    service = CFSocketCreate(NULL, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)AcceptCallBack, &CTX);
    if (service == NULL) {
        return;
    }
    //设置是否重新绑定标志
    int yes = 1;
    /* 设置socket属性 SOL_SOCKET是设置tcp SO_REUSEADDR是重新绑定，yes 是否重新绑定*/
    setsockopt(CFSocketGetNative(service), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));
    
    //设置端口和地址
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));       //memset函数对指定的地址进行内存拷贝
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;            //AF_INET是设置 IPv4
    addr.sin_port = htons(self.kPORT);    //htons函数 无符号短整型数转换成“网络字节序”
    addr.sin_addr.s_addr = htonl(INADDR_ANY);  //INADDR_ANY有内核分配，htonl函数 无符号长整型数转换成“网络字节序”
    
    /* 从指定字节缓冲区复制，一个不可变的CFData对象*/
    CFDataRef address = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&addr, sizeof(addr));
    
    /* 设置Socket*/
    if (CFSocketSetAddress(service, (CFDataRef)address) != kCFSocketSuccess) {
        fprintf(stderr, "Socket绑定失败\n");
        CFRelease(service);
        return ;
    }
    /* 创建一个Run Loop Socket源 */
    CFRunLoopSourceRef sourceRef = CFSocketCreateRunLoopSource(kCFAllocatorDefault, service, 0);
    /* Socket源添加到Run Loop中 */
    CFRunLoopAddSource(CFRunLoopGetCurrent(), sourceRef, kCFRunLoopCommonModes);
    CFRelease(sourceRef);
    
    printf("Socket listening on port %zd\n", self.kPORT);
    /* 运行Loop */
    CFRunLoopRun();

    
}

//接受客户端请求后回调函数
void AcceptCallBack(
                    CFSocketRef socket,
                    CFSocketCallBackType type,
                    CFDataRef address,
                    const void *data,
                    void *info)
{
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    //data参数的含义是，如果是kCFSocketAcceptCallBack类型，data是CFSocketNativeHandle类型的指针
    CFSocketNativeHandle sock = *(CFSocketNativeHandle *) data;
    
    //创建读写socket流
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, sock, &readStream, &writeStream);
    
    if (!readStream || !writeStream) {
        close(sock);
        fprintf(stderr, "CFStreamCreatePairWithSocket() 失败\n");
        return;
    }
    
    CFStreamClientContext streamCtxt = {0,NULL,NULL,NULL,NULL};
    //注册两种回调函数
    CFReadStreamSetClient(readStream, kCFStreamEventHasBytesAvailable, ReadStreamClientCallBack, &streamCtxt);
    CFWriteStreamSetClient(writeStream, kCFStreamEventCanAcceptBytes, WriteStreamClientCallBack, &streamCtxt);
    
    //加入到循环当中
    CFReadStreamScheduleWithRunLoop(readStream, CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
    CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
    
    CFReadStreamOpen(readStream);
    CFWriteStreamOpen(writeStream);

}

//读取操作，读取客户端发送的数据
static UInt8 buff[255];
void ReadStreamClientCallBack (CFReadStreamRef stream,CFStreamEventType eventType, void* clientCallBackInfo ) {
    
    CFReadStreamRef inputStream = stream;
    
    if (NULL != inputStream) {
        CFReadStreamRead(inputStream, buff, 255);
        printf("接收到的数据 :%s\n", buff);
        CFReadStreamClose(inputStream);
        //从循环中移除
        CFReadStreamUnscheduleFromRunLoop(inputStream, CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
        inputStream = NULL;
    }
    
}

/* 写入流操作 客户端在读取数据时候调用 */
void WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType eventType, void* clientCallBackInfo)
{
    CFWriteStreamRef    outputStream = stream;
    //输出
    UInt8 buff[] = "你是哪个？";
    if(NULL != outputStream)
    {
        CFWriteStreamWrite(outputStream, buff, strlen((const char*)buff)+1);
        //关闭输出流
        CFWriteStreamClose(outputStream);
        //从循环中移除
        CFWriteStreamUnscheduleFromRunLoop(outputStream, CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
        outputStream = NULL;
    }
}




@end
