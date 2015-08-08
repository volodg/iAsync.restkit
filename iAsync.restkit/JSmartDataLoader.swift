//
//  JSmartDataLoader.swift
//  JRestKit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_async
import iAsync_utils

extension NSObject {
    
    //TODO give him long name
    func logResponse() {
        NSLog("jsResponse: \(self)")
    }
}

extension NSData {
    
    override func logResponse() {
        
        let str = NSString(data:self, encoding:NSUTF8StringEncoding)
        NSLog("jsResponse: \(str) length: \(length)")
    }
}

public class JSmartDataLoaderFields<Identifier, AsyncResult> {
    
    public typealias JAsyncBinderForIdentifier = (loadDataIdentifier: Identifier) -> AsyncTypes2<NSData, AsyncResult, NSError>.JAsyncBinder
    public typealias JCacheKeyForIdentifier    = (loadDataIdentifier: Identifier) -> String
    
    let loadDataIdentifier: Identifier
    let dataLoaderForIdentifier: AsyncTypes2<Identifier, NSData, NSError>.JAsyncBinder
    let analyzerForData: JAsyncBinderForIdentifier
    let cacheKeyForIdentifier: JCacheKeyForIdentifier
    let doesNotIgnoreFreshDataLoadFail: Bool
    let cache: JAsyncRestKitCache
    let cacheDataLifeTimeInSeconds: NSTimeInterval
    
    public init(
        loadDataIdentifier: Identifier,
        dataLoaderForIdentifier: AsyncTypes2<Identifier, NSData, NSError>.JAsyncBinder,
        analyzerForData: JAsyncBinderForIdentifier,
        cacheKeyForIdentifier: JCacheKeyForIdentifier,
        doesNotIgnoreFreshDataLoadFail: Bool,
        cache: JAsyncRestKitCache,
        cacheDataLifeTimeInSeconds: NSTimeInterval)
    {
        self.loadDataIdentifier             = loadDataIdentifier
        self.dataLoaderForIdentifier        = dataLoaderForIdentifier
        self.analyzerForData                = analyzerForData
        self.cacheKeyForIdentifier          = cacheKeyForIdentifier
        self.doesNotIgnoreFreshDataLoadFail = doesNotIgnoreFreshDataLoadFail
        self.cache                          = cache
        self.cacheDataLifeTimeInSeconds     = cacheDataLifeTimeInSeconds
    }
}

public func jSmartDataLoaderWithCache<Identifier, AsyncResult>(args: JSmartDataLoaderFields<Identifier, AsyncResult>) -> AsyncTypes<AsyncResult, NSError>.Async {
    
    let loadDataIdentifier             = args.loadDataIdentifier
    let dataLoaderForIdentifier        = args.dataLoaderForIdentifier
    let analyzerForData                = args.analyzerForData
    let cache                          = args.cache
    let cacheKeyForIdentifier          = args.cacheKeyForIdentifier
    let cacheDataLifeTimeInSeconds     = args.cacheDataLifeTimeInSeconds
    let doesNotIgnoreFreshDataLoadFail = args.doesNotIgnoreFreshDataLoadFail
    
    let key = cacheKeyForIdentifier(loadDataIdentifier: loadDataIdentifier)
    
    let cachedDataLoader = { (progressCallback: AsyncProgressCallback?,
                              stateCallback   : AsyncChangeStateCallback?,
                              finishCallback  : AsyncTypes<JRestKitCachedData, NSError>.JDidFinishAsyncCallback?) -> JAsyncHandler in
        
        let loadCachedData = loadFreshCachedDataWithUpdateDate(
            key,
            cache.cachedDataLoaderForKey(key),
            cacheDataLifeTimeInSeconds)
        
        let dataLoaderBinder = dataLoaderWithCachedResultBinder(
            doesNotIgnoreFreshDataLoadFail,
            dataLoaderForIdentifier,
            loadDataIdentifier)
        
        let loader = bindTrySequenceOfAsyncs(loadCachedData, dataLoaderBinder)
        
        return loader(
            progressCallback: progressCallback,
            stateCallback   : stateCallback,
            finishCallback  : finishCallback)
    }
    
    let analyzer = { (response: JRestKitCachedData) -> AsyncTypes<AsyncResult, NSError>.Async in
        
        let binder = analyzerForData(loadDataIdentifier: loadDataIdentifier)
        
        let analyzer = binder(response.data)
        
        let cacheBinder = { (analyzedData: AsyncResult) -> AsyncTypes<AsyncResult, NSError>.Async in
            
            let resultLoader: AsyncTypes<AsyncResult, NSError>.Async = asyncWithResult(analyzedData)
            
            if response.updateDate == nil {
                let loader = cache.loaderToSetData(response.data, forKey:key)
                return sequenceOfAsyncs(loader, resultLoader)
            }
            return resultLoader
        }
        
        return bindSequenceOfAsyncs(analyzer, cacheBinder)
    }
    
    return bindSequenceOfAsyncs(cachedDataLoader, analyzer)
}

internal class ErrorNoFreshData : Error {
    
    let cachedData: JRestKitCachedData!
    
    override class func jffErrorsDomain() -> String {
        return "com.just_for_fun.rest_kit_internal.library"
    }
    
    required init(cachedData: JRestKitCachedData) {
        
        self.cachedData = cachedData
        super.init(description: "internal logic error (no fresh data)")
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func copyWithZone(zone: NSZone) -> AnyObject {
        
        return self.dynamicType(cachedData: cachedData)
    }
}

private func dataLoaderWithCachedResultBinder<Identifier>(
    doesNotIgnoreFreshDataLoadFail: Bool,
    dataLoaderForIdentifier: AsyncTypes2<Identifier, NSData, NSError>.JAsyncBinder,
    loadDataIdentifier: Identifier) -> AsyncTypes2<NSError, JRestKitCachedData, NSError>.JAsyncBinder
{
    return { (bindError: NSError) -> AsyncTypes<JRestKitCachedData, NSError>.Async in
        
        let finishCallbackHook = { (result: AsyncResult<NSData, NSError>, doneCallback: AsyncTypes<JRestKitCachedData, NSError>.JDidFinishAsyncCallback?) -> () in
            
            switch result {
            case let .Success(v):
                //logs [ srvResponse_ logResponse ];
                let newResult = JResponseDataWithUpdateData(data: v.value, updateDate: nil)
                doneCallback?(result: AsyncResult.success(newResult))
            case let .Failure(error):
                //TODO test [bindError isKindOfClass:[JFFErrorNoFreshData class]] issue, here it can got - not data in cache error !!!
                if !doesNotIgnoreFreshDataLoadFail {
                    if let noFreshDataError = bindError as? ErrorNoFreshData {
                    
                        let newResult = JResponseDataWithUpdateData(
                            data: noFreshDataError.cachedData.data,
                            updateDate: noFreshDataError.cachedData.updateDate)
                    
                        doneCallback?(result: AsyncResult.success(newResult))
                        return
                    }
                }
                
                doneCallback?(result: AsyncResult.failure(error.value))
            case .Interrupted:
                doneCallback?(result: .Interrupted)
            case .Unsubscribed:
                doneCallback?(result: .Unsubscribed)
            }
        }
        let dataLoader = dataLoaderForIdentifier(loadDataIdentifier)
        return asyncWithFinishHookBlock(dataLoader, finishCallbackHook)
    }
}

private func loadFreshCachedDataWithUpdateDate(
    key: String,
    cachedDataLoader: AsyncTypes<JRestKitCachedData, NSError>.Async,
    cacheDataLifeTimeInSeconds: NSTimeInterval) -> AsyncTypes<JRestKitCachedData, NSError>.Async
{
    let validateByDateResultBinder = { (cachedData: JRestKitCachedData) -> AsyncTypes<JRestKitCachedData, NSError>.Async in
        
        let newDate = cachedData.updateDate?.dateByAddingTimeInterval(cacheDataLifeTimeInSeconds)
        if newDate!.compare(NSDate()) == NSComparisonResult.OrderedDescending {
            return asyncWithResult(cachedData)
        }
        
        let error = ErrorNoFreshData(cachedData: cachedData)
        return asyncWithError(error)
    }
    
    return bindSequenceOfAsyncs(cachedDataLoader, validateByDateResultBinder)
}
