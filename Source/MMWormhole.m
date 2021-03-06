//
// MMWormhole.m
//
// Copyright (c) 2014 Mutual Mobile (http://www.mutualmobile.com/)
// Copyright (c) 2015 Radiant Tap (http://radianttap.com/)
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

#import "MMWormhole.h"

#if !__has_feature(objc_arc)
#error This class requires automatic reference counting
#endif

#include <CoreFoundation/CoreFoundation.h>

static NSString * const MMWormholeNotificationName = @"MMWormholeNotificationName";

@interface MMWormhole ()

@property (nonatomic, copy) NSString *applicationGroupIdentifier;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSUserDefaults *sharedDefaults;
@property (nonatomic, strong) NSMutableDictionary *listenerBlocks;

@property (nonatomic) MMWormholeStoreType storeType;

@end

@implementation MMWormhole

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (id)init {
    return nil;
}

#pragma clang diagnostic pop

- (instancetype)initWithApplicationGroupIdentifier:(NSString *)identifier
								 optionalDirectory:(NSString *)directory {
	
	if ([directory length] == 0) {
		directory = @"wormhole";
	}
	return [self initWithApplicationGroupIdentifier:identifier storeType:MMWormholeStoreTypeFile directory:directory];
}

- (instancetype)initWithApplicationGroupIdentifier:(NSString *)identifier storeType:(MMWormholeStoreType)storeType directory:(NSString *)directory {
    if ((self = [super init])) {
		
        if (NO == [[NSFileManager defaultManager] respondsToSelector:@selector(containerURLForSecurityApplicationGroupIdentifier:)]) {
            //Protect the user of a crash because of iOSVersion < iOS7
            return nil;
        }
        
		_storeType = storeType;
        _applicationGroupIdentifier = [identifier copy];
        _directory = [directory copy];
        _listenerBlocks = [NSMutableDictionary dictionary];
		
		switch (storeType) {
			case MMWormholeStoreTypeUserDefaults:
			{
				_fileManager = nil;
				_sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:self.applicationGroupIdentifier];
			}
				break;

			case MMWormholeStoreTypeFile:
			default:
			{
				_fileManager = [[NSFileManager alloc] init];
				_sharedDefaults = nil;
			}
				break;
		}
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMessageNotification:)
                                                     name:MMWormholeNotificationName
                                                   object:nil];
    }

    return self;
}

- (NSUserDefaults *)sharedDefaults {

	[_sharedDefaults synchronize];
	return _sharedDefaults;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveEveryObserver(center, (__bridge const void *)(self));
}


#pragma mark - Private File Operation Methods

- (NSString *)messagePassingDirectoryPath {
    NSURL *appGroupContainer = [self.fileManager containerURLForSecurityApplicationGroupIdentifier:self.applicationGroupIdentifier];
    NSString *appGroupContainerPath = [appGroupContainer path];
    NSString *directoryPath = appGroupContainerPath;
    
    if (self.directory != nil) {
        directoryPath = [appGroupContainerPath stringByAppendingPathComponent:self.directory];
    }
    
    [self.fileManager createDirectoryAtPath:directoryPath
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:NULL];
    
    return directoryPath;
}

- (NSString *)filePathForIdentifier:(NSString *)identifier {
    if (identifier == nil || identifier.length == 0) {
        return nil;
    }
    
    NSString *directoryPath = [self messagePassingDirectoryPath];
    NSString *fileName = [NSString stringWithFormat:@"%@.archive", identifier];
    NSString *filePath = [directoryPath stringByAppendingPathComponent:fileName];
    
    return filePath;
}

- (void)writeMessageObject:(id)messageObject toFileWithIdentifier:(NSString *)identifier {
    if (identifier == nil) {
        return;
    }
    
    if (messageObject) {
		switch (self.storeType) {
			case MMWormholeStoreTypeUserDefaults:
			{
				NSUserDefaults *def = [self sharedDefaults];
				[def setObject:messageObject forKey:[self.directory stringByAppendingString:identifier]];
				[def synchronize];
			}
				break;
				
			case MMWormholeStoreTypeFile:
			default:
			{
				NSData *data = [NSKeyedArchiver archivedDataWithRootObject:messageObject];
				NSString *filePath = [self filePathForIdentifier:identifier];
				
				if (data == nil || filePath == nil) {
					return;
				}
				
				BOOL success = [data writeToFile:filePath atomically:YES];
				
				if (!success) {
					return;
				}
			}
				break;
		}
    }
	
    [self sendNotificationForMessageWithIdentifier:identifier];
}

- (id)messageObjectFromFileWithIdentifier:(NSString *)identifier {
    if (identifier == nil) {
        return nil;
    }
	
	id messageObject = nil;
	
	switch (self.storeType) {
		case MMWormholeStoreTypeUserDefaults:
		{
			NSUserDefaults *def = [self sharedDefaults];
			messageObject = [def objectForKey:[self.directory stringByAppendingString:identifier]];
		}
			break;
			
		case MMWormholeStoreTypeFile:
		default:
		{
			NSData *data = [NSData dataWithContentsOfFile:[self filePathForIdentifier:identifier]];
			if (data == nil) {
				return nil;
			}
			messageObject = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		}
			break;
	}
	
    return messageObject;
}

- (void)deleteFileForIdentifier:(NSString *)identifier {

	switch (self.storeType) {
		case MMWormholeStoreTypeUserDefaults:
		{
			NSUserDefaults *def = [self sharedDefaults];
			[def removeObjectForKey:[self.directory stringByAppendingString:identifier]];
			[def synchronize];
		}
			break;
			
		case MMWormholeStoreTypeFile:
		default:
		{
			[self.fileManager removeItemAtPath:[self filePathForIdentifier:identifier] error:NULL];
		}
			break;
	}
}


#pragma mark - Private Notification Methods

- (void)sendNotificationForMessageWithIdentifier:(NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFDictionaryRef const userInfo = NULL;
    BOOL const deliverImmediately = YES;
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterPostNotification(center, str, NULL, userInfo, deliverImmediately);
}

- (void)registerForNotificationsWithIdentifier:(NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)(self),
                                    wormholeNotificationCallback,
                                    str,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)unregisterForNotificationsWithIdentifier:(NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterRemoveObserver(center,
                                       (__bridge const void *)(self),
                                       str,
                                       NULL);
}

void wormholeNotificationCallback(CFNotificationCenterRef center,
                               void * observer,
                               CFStringRef name,
                               void const * object,
                               CFDictionaryRef userInfo) {
    NSString *identifier = (__bridge NSString *)name;
    [[NSNotificationCenter defaultCenter] postNotificationName:MMWormholeNotificationName
                                                        object:nil
                                                      userInfo:@{@"identifier" : identifier}];
}

- (void)didReceiveMessageNotification:(NSNotification *)notification {
    typedef void (^MessageListenerBlock)(id messageObject);
    
    NSDictionary *userInfo = notification.userInfo;
    NSString *identifier = [userInfo valueForKey:@"identifier"];
    
    if (identifier != nil) {
        MessageListenerBlock listenerBlock = [self listenerBlockForIdentifier:identifier];

        if (listenerBlock) {
            id messageObject = [self messageObjectFromFileWithIdentifier:identifier];

            listenerBlock(messageObject);
        }
    }
}

- (id)listenerBlockForIdentifier:(NSString *)identifier {
    return [self.listenerBlocks valueForKey:identifier];
}


#pragma mark - Public Interface Methods

- (void)passMessageObject:(id <NSCoding>)messageObject identifier:(NSString *)identifier {
    [self writeMessageObject:messageObject toFileWithIdentifier:identifier];
}


- (id)messageWithIdentifier:(NSString *)identifier {
    id messageObject = [self messageObjectFromFileWithIdentifier:identifier];
    
    return messageObject;
}

- (void)clearMessageContentsForIdentifier:(NSString *)identifier {
    [self deleteFileForIdentifier:identifier];
}

- (void)clearAllMessageContents {
	//	unless directory is set, it's impossible to know which keys/files should be removed
	//	(directory should probably not be optional)
	if (self.directory == nil) return;

	switch (self.storeType) {
		case MMWormholeStoreTypeUserDefaults:
		{
			NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
				return [key containsString:self.directory];
			}];
			NSUserDefaults *def = [self sharedDefaults];
			NSArray *arr = [[[def dictionaryRepresentation] allKeys] filteredArrayUsingPredicate:predicate];
			for (NSString *key in arr) {
				[def removeObjectForKey:key];
			}
			[def synchronize];
		}
			break;
			
		case MMWormholeStoreTypeFile:
		default:
		{
			NSArray *messageFiles = [self.fileManager contentsOfDirectoryAtPath:[self messagePassingDirectoryPath] error:NULL];
			NSString *directoryPath = [self messagePassingDirectoryPath];
			
			for (NSString *path in messageFiles) {
				NSString *filePath = [directoryPath stringByAppendingPathComponent:path];
				[self.fileManager removeItemAtPath:filePath error:NULL];
			}
		}
			break;
	}
}

- (void)listenForMessageWithIdentifier:(NSString *)identifier
                              listener:(void (^)(id messageObject))listener {
    if (identifier != nil) {
        [self.listenerBlocks setValue:listener forKey:identifier];
        [self registerForNotificationsWithIdentifier:identifier];
    }
}

- (void)stopListeningForMessageWithIdentifier:(NSString *)identifier {
    if (identifier != nil) {
        [self.listenerBlocks setValue:nil forKey:identifier];
        [self unregisterForNotificationsWithIdentifier:identifier];
    }
}

@end
