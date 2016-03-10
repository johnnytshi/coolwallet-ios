//
//  NotifyManager.m
//  CoolWallet
//
//  Created by 鄭斐文 on 2016/3/8.
//  Copyright © 2016年 MAC-BRYAN. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "NotifyManager.h"
#import "SWRevealViewController.h"
#import "CwExchange.h"
#import "CwCard.h"
#import "CwExUnclarifyOrder.h"
#import "CwExUnblock.h"

#import "UIViewController+Utils.h"
#import "NSUserDefaults+RMSaveCustomObject.h"
#import "NSString+HexToData.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@implementation NotifyManager

-(void) process:(NSDictionary *)apsInfo
{
    NSDictionary *aps = [apsInfo objectForKey:@"aps"];
    if (aps.count == 0) {
        return;
    }
    
    NSDictionary *data = [apsInfo objectForKey:@"data"];
    NSString *cwid = [data objectForKey:@"cwid"];
    
    NSString *action = [data objectForKey:@"action"];
    NSString *orderID = [data objectForKey:@"order"];
    
    if ([action isEqualToString:@"blockOTP"]) {
        NSNumber *amount = [data objectForKey:@"amount"];
        NSNumber *price = [data objectForKey:@"price"];
        
        CwExUnclarifyOrder *unclarifyOrder = [CwExUnclarifyOrder new];
        unclarifyOrder.orderID = orderID;
        unclarifyOrder.amount = amount;
        unclarifyOrder.price = price;
        
        [self blockOTPFromCwID:cwid withUnclarifyOrder:unclarifyOrder];
    } else if ([action isEqualToString:@"cancelOrder"]) {
        [self cancelOrder:orderID fromCwID:cwid];
    } else if ([action isEqualToString:@"matchOrder"]) {
        [self matchOrder:orderID];
    }
    
    NSString *targetIdentifier;
    
    CwExchange *exchange = [CwExchange sharedInstance];
    if (exchange.sessionStatus == ExSessionLogin && [exchange.card.cardId isEqualToString:cwid]) {
        if ([action isEqualToString:@"blockOTP"]) {
            targetIdentifier = @"ExBlockOrderViewController";
        } else if ([action isEqualToString:@"matchOrder"]) {
            targetIdentifier = @"ExMatchedOrderViewController";
        }
    }
    
    NSString *msg = [aps objectForKey:@"alert"];
    NSNumber *content_available = [aps objectForKey:@"content-available"];
    NSLog(@"%@, %@", content_available, msg);
    if (content_available.intValue == 1 && [msg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        return;
    }
    
    [self notifyMessage:msg targetIdentifier:targetIdentifier];
}

-(void) notifyMessage:(NSString *)message targetIdentifier:(NSString *)identifier
{
    NSLog(@"notifyMessage:%@, targetIdentifier:%@", message, identifier);
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"receive notify" message:message preferredStyle:UIAlertControllerStyleAlert];
    
    UIViewController *currentViewController = [UIViewController currentViewController];
    if (currentViewController && [currentViewController isKindOfClass:[SWRevealViewController class]]) {
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:cancelAction];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (identifier == nil) {
                return;
            }
            UIStoryboard *secondStoryBoard = [UIStoryboard storyboardWithName:@"Accounts" bundle:nil];
            UIViewController *nextViewController = (UIViewController *)[secondStoryBoard instantiateViewControllerWithIdentifier:identifier];
            
            SWRevealViewController *revealController = (SWRevealViewController *)currentViewController;
            [(UINavigationController *)revealController.frontViewController pushViewController:nextViewController animated:YES];
        }];
        [alertController addAction:okAction];
    } else {
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:okAction];
    }
    
    [currentViewController presentViewController:alertController animated:YES completion:nil];
}

-(void) blockOTPFromCwID:(NSString *)cwid withUnclarifyOrder:(CwExUnclarifyOrder *)unclarifyOrder
{
    NSString *key = [NSString stringWithFormat:@"unclarify_%@", cwid];
    
    NSMutableArray *unclarify_orders = [[NSUserDefaults standardUserDefaults] rm_customObjectForKey:key];
    if (unclarify_orders == nil) {
        unclarify_orders = [NSMutableArray new];
    }
    [unclarify_orders addObject:unclarifyOrder];
    
    [[NSUserDefaults standardUserDefaults] rm_setCustomObject:unclarify_orders forKey:key];
}

-(void) cancelOrder:(NSString *)orderID fromCwID:(NSString *)cwid
{
    NSString *key = [NSString stringWithFormat:@"unblock_%@", cwid];
    NSMutableArray *unblock_orders = [[NSUserDefaults standardUserDefaults] rm_customObjectForKey:key];
    
    CwExchange *exchange = [CwExchange sharedInstance];
    if (exchange.sessionStatus == ExSessionLogin && exchange.card.cardId == cwid) {
        [[[exchange signalRequestUnblockInfo] flattenMap:^RACStream *(NSArray *unblocks) {
            for (CwExUnblock *unblock in unblocks) {
                if ([[NSString dataToHexstring:unblock.orderID] isEqualToString:orderID]) {
                    return [exchange signalUnblockWithCard:unblock];
                }
            }
            
            return [RACSignal empty];
        }] subscribeNext:^(id value) {
            NSLog(@"unblock success");
            if ([unblock_orders containsObject:orderID]) {
                [unblock_orders removeObject:orderID];
            }
        } error:^(NSError *error) {
            NSLog(@"unblock error: %@", error);
            if (![unblock_orders containsObject:orderID]) {
                [unblock_orders addObject:orderID];
            }
        }];
    } else {
        if (![unblock_orders containsObject:orderID]) {
            [unblock_orders addObject:orderID];
        }
    }
    
    [[NSUserDefaults standardUserDefaults] rm_setCustomObject:unblock_orders forKey:key];
}

-(void) matchOrder:(NSString *)orderID
{
    
}

@end