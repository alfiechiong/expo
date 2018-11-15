// Copyright © 2018 650 Industries. All rights reserved.

#import <EXPermissions/EXLocalNotificationRequester.h>
#import <EXCore/EXUtilities.h>

#import <UIKit/UIKit.h>

@interface EXLocalNotificationRequester ()

@property (nonatomic, strong) EXPromiseResolveBlock resolve;
@property (nonatomic, strong) EXPromiseRejectBlock reject;
@property (nonatomic, weak) id<EXPermissionRequesterDelegate> delegate;

@end

@implementation EXLocalNotificationRequester

+ (NSDictionary *)permissions
{
  __block BOOL allowsSound;
  __block BOOL allowsAlert;
  __block BOOL allowsBadge;
  [EXUtilities performSynchronouslyOnMainThread:^{
    allowsSound = [EXLocalNotificationRequester notificationTypeIsAllowed:UIUserNotificationTypeSound];
    allowsAlert = [EXLocalNotificationRequester notificationTypeIsAllowed:UIUserNotificationTypeAlert];
    allowsBadge = [EXLocalNotificationRequester notificationTypeIsAllowed:UIUserNotificationTypeBadge];
  }];
  
  EXPermissionStatus status = EXPermissionStatusUndetermined;
  
  // If the user allowed alerts we say that notifications are allowed
  if (allowsAlert) {
    status = EXPermissionStatusGranted;
  } else if (!allowsBadge && !allowsSound) {
    // However, if none of the notification types is allowed, we say the permission has been denied
    status = EXPermissionStatusDenied;
  }

  return @{
           @"status": [EXPermissions permissionStringForStatus:status],
           @"allowsSound": @(allowsSound),
           @"allowsAlert": @(allowsAlert),
           @"allowsBadge": @(allowsBadge),
           @"expires": EXPermissionExpiresNever,
           };
}

+ (BOOL)notificationTypeIsAllowed:(UIUserNotificationType)type
{
  UIUserNotificationSettings *currentSettings = EXSharedApplication().currentUserNotificationSettings;
  return (currentSettings.types & type) != 0;
}

- (void)requestPermissionsWithResolver:(EXPromiseResolveBlock)resolve rejecter:(EXPromiseRejectBlock)reject
{
  if (_resolve != nil || _reject != nil) {
    reject(@"E_AWAIT_PROMISE", @"Another request for the same permission is already being handled.", nil);
    return;
  }

  _resolve = resolve;
  _reject = reject;

  __block BOOL alertIsAllowed;

  [EXUtilities performSynchronouslyOnMainThread:^{
    alertIsAllowed = [EXLocalNotificationRequester notificationTypeIsAllowed:UIUserNotificationTypeAlert];
  }];

  if (alertIsAllowed) {
    // resolve immediately if already allowed
    [self _consumeResolverWithCurrentPermissions];
  } else {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleDidRegisterUserNotificationSettings:)
                                                 name:@"kEXAppDidRegisterUserNotificationSettingsNotification"
                                               object:nil];
    UIUserNotificationType types = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;
    dispatch_async(dispatch_get_main_queue(), ^{
      [EXSharedApplication() registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:types categories:nil]];
    });
  }
}

- (void)setDelegate:(id<EXPermissionRequesterDelegate>)delegate
{
  _delegate = delegate;
}

- (void)_handleDidRegisterUserNotificationSettings:(__unused NSNotification *)notif
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self _consumeResolverWithCurrentPermissions];
}

- (void)_consumeResolverWithCurrentPermissions
{
  if (_resolve) {
    _resolve([[self class] permissions]);
    _resolve = nil;
    _reject = nil;
  }
  if (_delegate) {
    [_delegate permissionRequesterDidFinish:self];
  }
}

@end