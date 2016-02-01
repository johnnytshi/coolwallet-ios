//
//  ExchangeViewController.m
//  CoolWallet
//
//  Created by 鄭斐文 on 2016/1/12.
//  Copyright © 2016年 MAC-BRYAN. All rights reserved.
//

#import "TabExchangeViewController.h"
#import "CwExchange.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

#define ExSignUpURL @"http://xsm.coolbitx.com:8080/signup"

@interface TabExchangeViewController ()

@end

@implementation TabExchangeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    UIImage* myImage = [UIImage imageNamed:@"ex_icon.png"];
    UIImageView* myImageView = [[UIImageView alloc] initWithImage:myImage];
    
    float x = self.navigationController.navigationBar.frame.size.width/2 - 90;
    myImageView.frame = CGRectMake(x, 8, 30, 30);
    [self.navigationController.navigationBar addSubview:myImageView];
    
    CwExchange *exchange = [CwExchange sharedInstance];
    @weakify(self)
    [[[[RACObserve(exchange, sessionStatus) filter:^BOOL(NSNumber *status) {
        return status.intValue == ExSessionLogin;
    }] take:1]
      subscribeOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(id value) {
         @strongify(self)
         [self performDismiss];
         [self performSegueWithIdentifier:@"ExLoginSegue" sender:self];
    }];
    
    if (exchange.sessionStatus == ExSessionProcess) {
        [self showIndicatorView:@"login exchange site"];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)signupEx:(id)sender {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:ExSignUpURL]];
}


@end
