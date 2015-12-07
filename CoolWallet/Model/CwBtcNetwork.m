//
//  CWBTCNetwork.m
//  iphone_app
//
//  Created by LIN CHIH-HUNG on 2014/10/18.
//  Copyright (c) 2014年 LIN CHIH-HUNG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CwBtcNetwork.h"
//Used to receive balance change notification from block.io
//#import "SRWebSocket.h"
#import "SRWebSocket+CW.h"
#import "CwManager.h"
#import "CwCard.h"
#import "CwAccount.h"
#import "CwAddress.h"
#import "CwTx.h"
#import "CwTxin.h"
#import "CwTxout.h"
#import "CwUnspentTxIndex.h"
#import "OCAppCommon.h"

#import "NSUserDefaults+RMSaveCustomObject.h"
#import "NSString+HexToData.h"

static const NSString *serverSite        = @"https://btc.blockr.io/api/v1";
//static const NSString *serverSite        = @"http://btc-blockr-io-soziedsyodjk.runscope.net/api/v1";
static const NSString *currencyURLStr    = @"exchangerate/current";
static const NSString *decodeURLStr      = @"tx/decode";
static const NSString *pushURLStr        = @"tx/push";
static const NSString *balanceURLStr     = @"address/balance"; //query multiple address with ?confirmations=0
static const NSString *allTxsURLStr      = @"address/txs";     //query address txs, get the txs detail by tx/info
static const NSString *unspentTxsURLStr  = @"address/unspent"; //query unspent, with ?unconfirmed=1
static const NSString *unconfirmTxsURLStr = @"address/unconfirmed"; //query address unconfirmed txs, get the txs detail by tx/info
static const NSString *txInfoURLStr      = @"tx/info";         //query tx infos

@interface CwBtcNetWork ()  <CWSocketDelegate>
@end

BOOL didGetTransactionByAccountFlag[5];

@implementation CwBtcNetWork
{
    SRWebSocket *_webSocket;
    CwManager *cwManager;
    CwCard *cwCard;
}

#pragma mark - Singleton methods
+(id) sharedManager {
    static CwBtcNetWork *sharedCwManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{sharedCwManager = [[self alloc] init];});
    return sharedCwManager;
}


- (id) init
{
    self = [super init];
    
    //connect to websocket
//    _webSocket.delegate = nil;
//    [_webSocket close];
//    
//    _webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"wss://n.block.io/"]]];
//    _webSocket.delegate = self;
//    
//    [_webSocket open];
    
    _webSocket = [SRWebSocket sharedSocket];
    _webSocket.cwDelegate = self;
    
    //prepare cwCard
    cwManager = [CwManager sharedManager];
    
    return self;
}

#pragma mark - CWSocketDelegate

-(void) didSocketReceiveMessage:(id)message
{
    NSError *_err = nil;
    
    NSLog(@"Websocket Received \"%@\"", message);
    
    cwCard = cwManager.connectedCwCard;
    
    //Got Balance Update Message
    //Update Address Balance
    //call delegate if others needs it
    //Add a notification to the system
    
    NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&_err];
    NSLog(@"didReceiveMessage: %@", JSON);
    if(_err || ![@"address" isEqualToString:JSON[@"type"]] || !(JSON[@"data"]))
    {
        return;
    }
    else
    {
        /*
         {
         "type": "address",
         "data": {
         "network": "BTC",
         "address": "3cBraN1Q...",
         "balance_change": "0.01000000", // net balance change, can be negative
         "amount_sent": "0.00000000",
         "amount_received": "0.01000000",
         "txid": "7af5cf9f2...", // the transaction's identifier (hash)
         "confirmations": X, // X = {0,1,3} for Bitcoin
         "is_green": false // was the transaction sent by a green address?
         }
         }
         */
        
        NSString *addr = JSON[@"data"][@"address"];
        
        int64_t balanceChangeNum = (int64_t)([JSON[@"data"][@"balance_change"] doubleValue] * 1e8 + ([JSON[@"data"][@"balance_change"] doubleValue]<0.0? -.5:.5));
        CwBtc *balanceChange = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:balanceChangeNum]];
        
        int64_t amountReceivedNum = (int64_t)([JSON[@"data"][@"amount_received"] doubleValue] * 1e8 + ([JSON[@"data"][@"amount_received"] doubleValue]<0.0? -.5:.5));
        CwBtc *amountReceived = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountReceivedNum]];
        //CwBtc *amountSend = [CwBtc BTCWithBTC:[NSNumber numberWithFloat:[JSON[@"data"][@"amount_sent"] floatValue]]];
        
        NSNumber *confirmations = JSON[@"data"][@"confirmations"];
        
        //find addr in accounts
        BOOL foundAddr = NO;
        NSInteger foundAccId = -1;
        NSInteger foundExtInt = 0;
        
        for (int a=0; a<cwCard.cwAccounts.count; a++)
        {
            CwAccount *acc = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%d", a]];
            
            for (int i=0; i<acc.extKeys.count; i++) {
                CwAddress *add =acc.extKeys[i];
                if ([add.address isEqualToString:addr]) {
                    foundAccId = acc.accId;
                    foundAddr = YES;
                    foundExtInt = 0; //External Key
                    break;
                }
            }
            if (!foundAddr) {
                for (int i=0; i<acc.intKeys.count; i++) {
                    CwAddress *add =acc.intKeys[i];
                    if ([add.address isEqualToString:addr]) {
                        foundAccId = acc.accId;
                        foundAddr = YES;
                        foundExtInt = 1; //Internal Key                        
                        break;
                    }
                }
            }
            
            if (foundAddr) {
                BOOL tidExist = NO;
                NSString *tid = JSON[@"data"][@"txid"];
                NSData *tidData = [NSString hexstringToData:tid];
                for (NSData *txid in acc.transactions) {
                    if ([tidData isEqualToData:txid]) {
                        tidExist = YES;
                        break;
                    }
                }
                
                if (!tidExist && acc.lastUpdate != nil) {
                    acc.balance = acc.balance + [balanceChange.satoshi integerValue];
                    [cwCard.cwAccounts setObject:acc forKey:[NSString stringWithFormat: @"%ld", acc.accId]];
                    [cwCard setAccount:acc.accId Balance:acc.balance];
                }
                
                [self performSelectorInBackground:@selector(updateHistoryTxs:) withObject:tid];
                
                break;
            }
        }
        
        //set notification if receive bitcoin in external address)
        if (foundAddr && balanceChange.satoshi.intValue>0 && foundExtInt==0)
        {
            UILocalNotification *notify = [[UILocalNotification alloc] init];
            notify.userInfo = @{@"title": @"Bitcoin Received"};
            
            if ([amountReceived.satoshi intValue]!=0) {
                notify.alertBody = [NSString stringWithFormat:@"Account %ld\nAddress: %@\nReceived Amount: %@ %@\nConfirmations: %d", foundAccId+1, addr, [amountReceived getBTCDisplayFromUnit], [[OCAppCommon getInstance] BitcoinUnit], confirmations.intValue];
            }
            notify.soundName = UILocalNotificationDefaultSoundName;
            [[UIApplication sharedApplication] presentLocalNotificationNow: notify];
        }
    }
}

#pragma mark - Internal Functions

- (NSData*) HTTPRequestUsingGETMethodFrom:(NSString*)urlStr err:(NSError**)_err response:(NSURLResponse**)_response
{
    NSURL *url = [[NSURL alloc]initWithString:urlStr];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    [httpRequest setURL:url];
    [httpRequest setHTTPMethod:@"GET"];
    [httpRequest setHTTPBody:nil];
    
    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:httpRequest];
    NSData *data = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:_response error:_err];
    
    return data;
}

#pragma marks - Functions

- (NSDictionary *) getCurrRate;//key: CurrId, value: rate
{
    GetCurrErr err = GETCURR_BASE;
    
    NSError *_err = nil;
    
    NSString *stringURL = [NSString stringWithFormat:@"%@/%@/",serverSite,currencyURLStr];
    NSURL *url = [NSURL URLWithString:stringURL];
    NSData *data = [NSData dataWithContentsOfURL:url];
    
    if(data)
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(_err || ![@"success" isEqualToString:JSON[@"status"]] || !(JSON[@"data"][0][@"rates"]))
        {
            err = CETCURR_JSON;
        }
        else
        {
            err = GETCURR_BASE;
            NSMutableDictionary *rates = [JSON[@"data"][0][@"rates"] mutableCopy];
            
            //get BTC to USD rate
            NSNumber *btcRate = [rates objectForKey:@"BTC"];
            
            [rates removeObjectForKey:@"BTC"];
            
            [rates enumerateKeysAndObjectsUsingBlock: ^(id currId, id currRate, BOOL *stop) {
                currRate = [NSNumber numberWithFloat: (((NSNumber *)currRate).floatValue/((NSNumber *)btcRate).floatValue)];
                [rates setObject:currRate forKey:currId];
            }];
            
            /*
            for (NSString* currId in rates) {
                NSNumber *currRate = [rates objectForKey:currId];
                
                //calculate the rate against BTC
                currRate =[NSNumber numberWithFloat: (currRate.floatValue/btcRate.floatValue)];

                [rates setObject:currRate forKey:currId];
            }*/
            
            return rates;
        }
    }
    else
    {
        err = GETCURR_NETWORK;
    }
    
    return nil;
}

-(GetAllTxsByAddrErr) updateHistoryTxs:(NSString *)tid
{
    NSError *_err = nil;
    GetAllTxsByAddrErr err = GETALLTXSBYADDR_BASE;
    NSURLResponse *_response = nil;
    NSLog(@"updateHistoryTxs %@", tid);
    
    NSData *data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@",serverSite,txInfoURLStr,tid] err:&_err response:&_response];
    
    if(_err)
    {
        err = GETALLTXSBYADDR_NETWORK;
    }
    else
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        
        if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"]))
        {
            err = GETALLTXSBYADDR_JSON;
        }
        else
        {
            NSDictionary *data = [JSON objectForKey:@"data"];
            NSMutableArray *txs = [NSMutableArray new];
            for (NSDictionary *tx in [data objectForKey:@"vins"]) {
                [txs addObject:[tx objectForKey:@"address"]];
            }
            for (NSDictionary *tx in [data objectForKey:@"vouts"]) {
                [txs addObject:[tx objectForKey:@"address"]];
            }
            
            NSData* _tid = [NSString hexstringToData:tid];
            
            NSDateFormatter *dateformat = [[NSDateFormatter alloc]init];
            [dateformat setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
            [dateformat setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
            
            NSUInteger confirmations = [[data objectForKey:@"confirmations"] unsignedIntegerValue];
            NSDate *timeUTC = [dateformat dateFromString:[data objectForKey:@"time_utc"]];
            
            for (CwAccount *cwAccount in [cwCard.cwAccounts allValues]) {
                if (cwAccount.lastUpdate == nil) {
                    continue;
                }
                
                NSArray *txAddresses = [[cwAccount getAllAddresses] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.address in %@", txs]];
                
                if (txAddresses.count == 0) {
                    continue;
                }
                
                CwTx *historyTx = [cwAccount.transactions objectForKey:_tid];
                if (historyTx) {
                    [historyTx setConfirmations:[NSNumber numberWithUnsignedInteger:confirmations]];
                    [historyTx setHistoryTime_utc:timeUTC];
                    [cwAccount.transactions setObject:historyTx forKey:_tid];
                } else {
                    NSMutableArray *addresses = [NSMutableArray new];
                    for (CwAddress *cwaddr in txAddresses) {
                        [addresses addObject:cwaddr.address];
                        cwaddr.historyUpdateFinish = NO;
                    }
                    NSDictionary *updateTxs = [self queryHistoryTxs:addresses];
                    [self syncAccountTransactions:updateTxs account:cwAccount];
                }
                
                for (CwAddress *cwAddr in txAddresses) {
                    NSLog(@"check '%@' unspent", cwAddr.address);
                    [self getUnspentByAddress:cwAddr fromAccount:cwAccount];
                }
            }
        }
    }
    
    return err;
}

- (GetTransactionByAccountErr) getTransactionByAccount:(NSInteger)accId
{
    GetTransactionByAccountErr err = GETTRXBYACCT_BASE;
    
    didGetTransactionByAccountFlag[accId] = NO;
    
    NSLog(@"Get Transaction By Account %ld", (long)accId);
    
    cwCard = cwManager.connectedCwCard;

    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    
    if (account.transactions == nil) {
        account.transactions = [[NSMutableDictionary alloc] init];
    }
    
    if (account.unspentTxs == nil) {
        account.unspentTxs = [[NSMutableArray alloc] init];
    }
    
    [self getHistoryTxsByAccount:account];
    
    for (CwAddress *address in [account getAllAddresses]) {
        if (address.historyTrx != nil && address.historyTrx.count == 0) {
            continue;
        }
        [self getUnspentByAddress:address fromAccount:account];
    }

    return err;
}

-(void) syncAccountTransactions:(NSDictionary *)historyTxData account:(CwAccount *)account
{
    for (CwAddress *cwAddress in [account getAllAddresses]) {
        NSArray *historyTxList = [historyTxData objectForKey:cwAddress.address];
        if (!historyTxList) {
            continue;
        }
        
        for (CwTx *htx in historyTxList)
        {
            CwTx *record = [account.transactions objectForKey:htx.tid];
            if(record)
            {
                //update amount
                NSLog(@"Update Trx %@ amount %@ with %@, conifrm: %@", record.tid, record.historyAmount.satoshi,  htx.historyAmount.satoshi, [htx confirmations]);
                
                if (cwAddress.historyTrx == nil) {
//                    record.historyAmount = [record.historyAmount add:htx.historyAmount];
                    CwBtc *btc = [record.historyAmount add:htx.historyAmount];
                    record.amount_btc = btc.BTC;
                } else {
                    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.tid == %@", htx.tid];
                    NSArray *searchResult = [cwAddress.historyTrx filteredArrayUsingPredicate:predicate];
                    
                    if (searchResult.count == 0) {
//                        record.historyAmount = [record.historyAmount add:htx.historyAmount];
                        CwBtc *btc = [record.historyAmount add:htx.historyAmount];
                        record.amount_btc = btc.BTC;
                    }
                }
                
                //update confirmations
                [record setConfirmations:[htx confirmations]];
                [record setHistoryTime_utc:htx.historyTime_utc];
                
                [account.transactions setObject:record forKey:record.tid];
            }
            else
            {
                //add new txs
                NSLog(@"Add New Trx %@ with amount %@", htx.tid, htx.historyAmount.satoshi);
                [account.transactions setObject:htx forKey:htx.tid];
            }
        }
        
        cwAddress.historyTrx = [NSMutableArray arrayWithArray:historyTxList];
        if (cwAddress.keyChainId == CwAddressKeyChainExternal) {
            account.extKeys[cwAddress.keyId] = cwAddress;
        } else {
            account.intKeys[cwAddress.keyId] = cwAddress;
        }
        
        cwAddress.historyUpdateFinish = YES;
    }
    
    [self isGetTransactionByAccount: account.accId];
}

-(void) getUnspentByAddress:(CwAddress *)addr fromAccount:(CwAccount *)account
{
    NSLog(@"getUnspentByAddress: %@, keyChainId is %ld", addr.address, addr.keyChainId);
    if (addr.keyChainId != CwAddressKeyChainExternal && addr.keyChainId != CwAddressKeyChainInternal) {
        return;
    }
    
    addr.unspendUpdateFinish = NO;
    
    dispatch_async(dispatch_queue_create("transaction.unspent", NULL), ^{
        
        //NSLog(@"Get UnspentTxsByAddr: %@", add.address);
        NSMutableArray *addrUnspentTxs;
        if([self getUnspentTxsByAddr:addr.address unspentTxs:&addrUnspentTxs]!= GETUNSPENTTXSBYADDR_BASE)
        {
            //err = GETTRXBYACCT_UNSPENTTX;
            //break;
        }
        else
        {
            //add txs to account
            for (CwUnspentTxIndex *unspentTxIndex in addrUnspentTxs)
            {
                unspentTxIndex.kId = [addr keyId];
                unspentTxIndex.kcId = [addr keyChainId];
                
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.tid == %@", unspentTxIndex.tid];
                NSArray *searchResult = [account.unspentTxs filteredArrayUsingPredicate:predicate];
                if (searchResult.count == 0) {
                    [account.unspentTxs addObject:unspentTxIndex];
                } else {
                    CwUnspentTxIndex *historyUnspentTxIndex = searchResult[0];
                    NSInteger index = [account.unspentTxs indexOfObject:historyUnspentTxIndex];
                    [account.unspentTxs replaceObjectAtIndex:index withObject:unspentTxIndex];
                }
            }
            
            if (addrUnspentTxs.count == 0) {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.kcId = %ld and SELF.kId = %d", (long)addr.keyChainId, addr.keyId];
                NSArray *predicateResult = [account.unspentTxs filteredArrayUsingPredicate:predicate];
                if (predicateResult.count > 0) {
                    [account.unspentTxs removeObjectsInArray:predicateResult];
                }
            }
        }
        
        addr.unspendUpdateFinish = YES;
        
        //save account back to cwCard
        [cwCard.cwAccounts setObject:account forKey:[NSString stringWithFormat: @"%ld", (long)account.accId]];
        
        //check if all addresses of account synced
        [self isGetTransactionByAccount: account.accId];
        
    });
    
}

- (void) isGetTransactionByAccount: (NSInteger) accId
{
    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    BOOL isGetTrx = YES;
    
    for (CwAddress *address in [account getAllAddresses]) {
        if (!address.historyUpdateFinish || !address.unspendUpdateFinish) {
            isGetTrx = NO;
            break;
        }
    }
    
    if (isGetTrx && !didGetTransactionByAccountFlag[accId]) {
        NSMutableArray *removedUnspents = [NSMutableArray new];
        for (CwUnspentTxIndex *unspent in account.unspentTxs) {
            NSLog(@"accId: %ld, unspent: %@,%ld,%ld,%ld, amount: %@", accId, [NSString dataToHexstring:unspent.tid], unspent.kcId, unspent.kId, unspent.n, unspent.amount);
            
            if (unspent.confirmations.intValue > 0) {
                continue;
            }
            
            CwTx *historyTx = [account.transactions objectForKey:unspent.tid];
            for (CwTxin *txin in historyTx.inputs) {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.tid == %@ and n = %ld", txin.tid, txin.n];
                NSArray *predicateResult = [account.unspentTxs filteredArrayUsingPredicate:predicate];
                [removedUnspents addObjectsFromArray:predicateResult];
            }
        }
        [account.unspentTxs removeObjectsInArray:removedUnspents];
        
        //Call Delegate
        if (self.delegate != nil && [self.delegate respondsToSelector:@selector(didGetTransactionByAccount:)]) {
            [self.delegate didGetTransactionByAccount:accId];
        }
        didGetTransactionByAccountFlag[accId] = YES;
        
        account.lastUpdate = [NSDate date];
    }
    
    return;
}

- (RegisterNotifyByAddrErr) registerNotifyByAccount: (NSInteger)accId
{
    RegisterNotifyByAddrErr err = REGNOTIFYBYADDR_BASE;
    
    cwCard = cwManager.connectedCwCard;
    
    CwAccount *account = [cwCard.cwAccounts objectForKey:[NSString stringWithFormat: @"%ld", (long)accId]];
    
    //add addresses to query string
    for (CwAddress *addr in [account getAllAddresses]) {
        [self registerNotifyByAddress:addr];
    }
    
    return err;
}

-(void) registerNotifyByAddress:(CwAddress *)addr
{
    if (addr.registerNotification) return;
    
    NSString *msg = [NSString stringWithFormat:@"{\"network\": \"BTC\",\"type\": \"address\",\"address\": \"%@\"}", addr.address];
    NSLog(@"WebNotify: %@", msg);
    [_webSocket send:msg];
    
    addr.registerNotification = YES;
}

-(NSDictionary *) getHistoryTxsByAccount:(CwAccount *)account
{
    NSMutableDictionary *result = [NSMutableDictionary new];
    
    NSMutableArray *allAddresses = [account getAllAddresses];
    NSMutableArray *paramAddresses = [NSMutableArray new];
    for (CwAddress *cwAddress in allAddresses) {
        cwAddress.historyUpdateFinish = NO;
        
        [paramAddresses addObject:cwAddress.address];
        if (paramAddresses.count < 20 && cwAddress != allAddresses.lastObject) {
            continue;
        }
        
        [result setValuesForKeysWithDictionary:[self queryHistoryTxs:paramAddresses]];
        
        [paramAddresses removeAllObjects];
    }
    
    [self syncAccountTransactions:result account:account];
    
    return result;
}

-(NSDictionary *) queryHistoryTxs:(NSArray *)addresses
{
    NSString *requestUrl = [NSString stringWithFormat:@"%@/%@/%@",serverSite,allTxsURLStr, [addresses componentsJoinedByString:@","]];
    
    NSDateFormatter *dateformat = [[NSDateFormatter alloc]init];
    [dateformat setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
    [dateformat setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    
    NSMutableDictionary *result = [NSMutableDictionary new];
    [self getRequestUrl:requestUrl params:nil success:^(NSDictionary *data) {
        NSNumber *code = [data objectForKey:@"code"];
        if (code.intValue != 200) {
            NSLog(@"fail: %@, from url: %@", [data objectForKey:@"message"], requestUrl);
            return;
        }
        
        if ([[data objectForKey:@"data"] isKindOfClass:[NSArray class]]) {
            NSArray *addrDataList = [data objectForKey:@"data"];
            for (NSDictionary *addrData in addrDataList) {
                NSString *address = [addrData objectForKey:@"address"];
                if ([address isEqualToString:@""]) {
                    continue;
                }
                
                NSArray *txs = [addrData objectForKey:@"txs"];
                NSMutableArray *addrTxs = [self getAddrTxs:txs];
                
                [result setObject:addrTxs forKey:address];
            }
        } else {
            NSDictionary *addrData = [data objectForKey:@"data"];
            NSString *address = [addrData objectForKey:@"address"];
            NSArray *txs = [addrData objectForKey:@"txs"];
            NSMutableArray *addrTxs = [self getAddrTxs:txs];
            [result setObject:addrTxs forKey:address];
        }
        
    } failure:^(NSError *err) {
        NSLog(@"error: %@", err.description);
    }];
    
    NSDictionary *unconfirmedTxs = [self queryUnConfirmedTxs:addresses];
    for (NSString *key in unconfirmedTxs) {
        NSArray *unconfirmedTx = [unconfirmedTxs objectForKey:key];
        if (unconfirmedTx.count == 0) {
            continue;
        }
        NSMutableArray *transactionTxs = [NSMutableArray arrayWithArray:[result objectForKey:key]];
        if (transactionTxs == nil) {
            transactionTxs = [NSMutableArray new];
        }
        [transactionTxs addObjectsFromArray:unconfirmedTx];
        [result setObject:transactionTxs forKey:key];
    }
    
    return result;
}

-(NSMutableArray *) getAddrTxs:(NSArray *)txs
{
    NSMutableArray *addrTxs = [NSMutableArray new];
    for (NSDictionary *txData in txs) {
        CwTx *tx = [self parseAddrTxData:txData];
        if (tx == nil) {
            continue;
        }
        [addrTxs addObject:tx];
    }
    
    return addrTxs;
}

-(NSDictionary *) queryUnConfirmedTxs:(NSArray *)addresses
{
    NSString *requestUrl = [NSString stringWithFormat:@"%@/%@/%@",serverSite,unconfirmTxsURLStr, [addresses componentsJoinedByString:@","]];
    
    NSDateFormatter *dateformat = [[NSDateFormatter alloc]init];
    [dateformat setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
    [dateformat setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    
    NSMutableDictionary *result = [NSMutableDictionary new];
    [self getRequestUrl:requestUrl params:nil success:^(NSDictionary *data) {
        NSNumber *code = [data objectForKey:@"code"];
        if (code.intValue != 200) {
            NSLog(@"fail: %@, from url: %@", [data objectForKey:@"message"], requestUrl);
            return;
        }
        
        if ([[data objectForKey:@"data"] isKindOfClass:[NSArray class]]) {
            NSArray *dataList = [data objectForKey:@"data"];
            for (NSDictionary *addrData in dataList) {
                NSArray *txs = [addrData objectForKey:@"unconfirmed"];
                NSMutableArray *addrTxs = [self getAddrTxs:txs];
                [result setObject:addrTxs forKey:[addrData objectForKey:@"address"]];
            }
        } else {
            NSDictionary *addrData = [data objectForKey:@"data"];
            NSArray *txs = [addrData objectForKey:@"unconfirmed"];
            NSMutableArray *addrTxs = [self getAddrTxs:txs];
            [result setObject:addrTxs forKey:[addrData objectForKey:@"address"]];
        }
        
    } failure:^(NSError *err) {
        NSLog(@"error: %@", err.description);
    }];
    
    return result;
}

- (GetUnspentTxsByAddrErr) getUnspentTxsByAddr:(NSString*)addr unspentTxs:(NSMutableArray**)unspentTxs
{
    GetUnspentTxsByAddrErr err = GETUNSPENTTXSBYADDR_BASE;
    NSError *_err;
    NSURLResponse *_response = nil;
    NSData *data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@?unconfirmed=1",serverSite,unspentTxsURLStr,addr] err:&_err response:&_response];
    
    NSLog(@"Get UnspentTxs by Address %@, err: %@", addr, _err);
    
    if(_err)
    {
        err = GETUNSPENTTXSBYADDR_NETWORK;
    }
    else
    {
        NSDictionary *JSON =[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(!(!_err && [@"success" isEqualToString:JSON[@"status"]] && JSON[@"data"] && JSON[@"data"][@"unspent"]))
        {
            NSLog(@"unspent error: %@", JSON);
            err = GETUNSPENTTXSBYADDR_JSON;
        }
        else
        {
            NSArray* rawUnspentTxs = JSON[@"data"][@"unspent"];
            NSMutableArray *_unspentTxs = [[NSMutableArray alloc] initWithCapacity:[rawUnspentTxs count]];
            
            for (NSDictionary *rawUnspentTx in rawUnspentTxs)
            {
                double amountValue = [rawUnspentTx[@"amount"] doubleValue];
                int64_t amountNum = (int64_t)(amountValue * 1e8 + (amountValue < 0.0 ? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                
                NSData* tid = [NSString hexstringToData:rawUnspentTx[@"tx"]];
                NSData* scriptPub = [NSString hexstringToData:rawUnspentTx[@"script"]];
                NSUInteger n = [rawUnspentTx[@"n"] unsignedIntegerValue];
                
                CwUnspentTxIndex *unspentTx = [[CwUnspentTxIndex alloc]init];
                unspentTx.tid = [NSData dataWithData:tid];
                unspentTx.n = n;
                unspentTx.amount = amount;
                unspentTx.scriptPub = scriptPub;
                unspentTx.confirmations = [NSNumber numberWithInteger:[[rawUnspentTx objectForKey:@"confirmations"] unsignedIntegerValue]];
                
                [_unspentTxs addObject:unspentTx];
                NSLog(@"    tid:%@ n:%lu amount:%@", tid, (unsigned long)n, amount.satoshi);
            }
            *unspentTxs = _unspentTxs;
        }
    }
    
    return err;
}

-(void) queryTxInfo:(NSString *)tid success:(void(^)(NSMutableArray *inputs, NSMutableArray *outputs))success fail:(void(^)(NSError *err))fail
{
    NSError *_err;
    NSURLResponse *_response;
    NSData *data = [self HTTPRequestUsingGETMethodFrom:[NSString stringWithFormat:@"%@/%@/%@", serverSite,txInfoURLStr,tid] err:&_err response:&_response];
    
    if (_err)
    {
        fail(_err);
        return;
    }
    else
    {
        NSDictionary *txDetail=[NSJSONSerialization JSONObjectWithData:data options:0 error:&_err];
        if(!(!_err && [@"success" isEqualToString:txDetail[@"status"]] && txDetail[@"data"]))
        {
            fail(_err);
            return;
        }
        else
        {
            NSArray *txIns = txDetail[@"data"][@"vins"];
            NSArray *txOuts = txDetail[@"data"][@"vouts"];
            
            NSMutableArray *inputs = [NSMutableArray new];
            NSMutableArray *outputs = [NSMutableArray new];
            
            for (NSDictionary *txIn in txIns)
            {
                NSString *address = txIn[@"address"];
                int64_t amountNum = (int64_t)([txIn[@"amount"] doubleValue] * 1e8 + ([txIn[@"amount"] doubleValue]<0.0? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                NSInteger n = [txIn[@"n"] integerValue];
                NSData* tid = [NSString hexstringToData:txIn[@"vout_tx"]];
                
                CwTxin *txin = [[CwTxin alloc] init];
                txin.tid = tid;
                txin.addr = address;
                txin.n = n;
                txin.amount = amount;
                
                [inputs addObject:txin];
            }
            
            for (NSDictionary *txOut in txOuts)
            {
                NSString *address = txOut[@"address"];
                int64_t amountNum = (int64_t)([txOut[@"amount"] doubleValue] * 1e8 + ([txOut[@"amount"] doubleValue]<0.0? -.5:.5));
                CwBtc* amount = [CwBtc BTCWithSatoshi: [NSNumber numberWithLongLong:amountNum]];
                
                NSInteger n = [txOut[@"n"] integerValue];
                BOOL isSpent = [txOut[@"is_spent"] boolValue];
                
                CwTxout *txout = [[CwTxout alloc] init];
                txout.addr = address;
                txout.amount = amount;
                txout.n = n;
                txout.isSpent = isSpent;
                
                [outputs addObject:txout];
            }
            
            success(inputs, outputs);
        }
    }
}

-(CwTx *) parseAddrTxData:(NSDictionary *)txData
{
    CwTx *tx = [RMMapper objectWithClass:[CwTx class] fromDictionary:txData];
    tx.txType = TypeHistoryTx;
    
    //get trxdetails
    [self performSelectorInBackground:@selector(queryTxDetail:) withObject:tx];
    
    NSLog(@"    tid:%@ amount:%@", tx.tid, tx.historyAmount.satoshi);
    
    return tx;
}

-(void) queryTxDetail:(CwTx *)tx
{
    CwTx *cachedTx = [[NSUserDefaults standardUserDefaults] rm_customObjectForKey:tx.tx];
    NSLog(@"queryTxDetail, %@, %@", tx.tx, cachedTx);
    if (cachedTx == nil || cachedTx.confirmations.intValue < 6 || cachedTx.inputs.count == 0 || cachedTx.outputs.count == 0) {
        NSString *tid = [NSString dataToHexstring:tx.tid];
        [self queryTxInfo:tid success:^(NSMutableArray *inputs, NSMutableArray *outputs) {
            [tx.inputs addObjectsFromArray:inputs];
            [tx.outputs addObjectsFromArray:outputs];
            
            [[NSUserDefaults standardUserDefaults] rm_setCustomObject:tx forKey:tx.tx];
        } fail:^(NSError *err) {
            NSLog(@"error %@ at query Tx info: %@", err, tid);
        }];
    } else {
        tx.inputs = cachedTx.inputs;
        tx.outputs = cachedTx.outputs;
        
        [[NSUserDefaults standardUserDefaults] rm_setCustomObject:tx forKey:tx.tx];
    }
}

- (PublishErr) publish:(CwTx*)tx result:(NSData **)result
{
    NSURL *connection = [[NSURL alloc]initWithString:[NSString stringWithFormat:@"%@/%@", serverSite, pushURLStr]];
    NSString *postString = [NSString stringWithFormat:@"{\"hex\":\"%@\"}",[NSString dataToHexstring:[tx rawTx]]];
    
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    NSLog(@"tx raw: %@", postString);
    
    [httpRequest setURL:connection];
    [httpRequest setHTTPMethod:@"POST"];
    [httpRequest setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *decodeTxJSON = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:nil error:nil];
    
    *result = [[NSData alloc] initWithData: decodeTxJSON];
    
    return PUBLISH_BASE;
}

//- (PublishErr) publish:(CwTx*)tx result:(NSData **)result
//{
//    NSURL *connection = [[NSURL alloc]initWithString:@"https://api-blockcypher-com-soziedsyodjk.runscope.net/v1/btc/main/txs/push"];
//    NSString *postString = [NSString stringWithFormat:@"{\"tx\":\"%@\"}",[self dataToHexstring:[tx rawTx]]];
//    
//    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
//    
//    NSLog(@"tx raw: %@", postString);
//    
//    [httpRequest setURL:connection];
//    [httpRequest setHTTPMethod:@"POST"];
//    [httpRequest setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
//    
//    NSData *decodeTxJSON = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:nil error:nil];
//    
//    *result = [[NSData alloc] initWithData: decodeTxJSON];
//    
//    return PUBLISH_BASE;
//}

- (GetCurrErr) getCurrency:(NSNumber**)currency
{
    // TODO ...
    return GETCURR_BASE;
}

- (DecodeErr) decode:(CwTx*)tx result:(NSData **)result
{
    NSURL *connection = [[NSURL alloc]initWithString:[NSString stringWithFormat:@"%@/%@", serverSite, decodeURLStr]];
    NSString *postString = [NSString stringWithFormat:@"{\"hex\":\"%@\"}",[NSString dataToHexstring:[tx rawTx]]];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc]init];
    
    NSLog(@"tx raw: %@", postString);
    
    [httpRequest setURL:connection];
    [httpRequest setHTTPMethod:@"POST"];
    [httpRequest setHTTPBody:[postString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *decodeTxJSON = [NSURLConnection sendSynchronousRequest:httpRequest returningResponse:nil error:nil];
    
    *result = [[NSData alloc] initWithData: decodeTxJSON];
    
    return DECODE_BASE;
}

-(void) getRequestUrl:(NSString *)url params:(NSDictionary *)params success:(void(^)(NSDictionary *json))success failure:(void(^)(NSError *err))failure
{
    if (params != nil && params.count > 0) {
        NSMutableArray *paramArray = [NSMutableArray new];
        for (NSString *key in params.keyEnumerator.allObjects) {
            NSString *value = [params objectForKey:key];
            [paramArray addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }
        
        url = [NSString stringWithFormat:@"%@?%@", url, [paramArray componentsJoinedByString:@"&"]];
    }
    
    NSURL *requestUrl = [NSURL URLWithString:[url stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
    //    NSData *data = [NSData dataWithContentsOfURL:requestUrl];
    
    NSURLResponse *_response = nil;
    NSError *_err = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:requestUrl];
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&_response error:&_err];
    
    if (data) {
        NSError *error;
        NSDictionary *json =[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
        if (json == nil) {
            failure(error);
        } else {
            success(json);
        }
    } else {
        failure(_err);
    }
}

@end