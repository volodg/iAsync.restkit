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

import Box

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

public enum DataRequestContext<DataLoadContext> {
    
    case Outside(Box<DataLoadContext>)
    case CacheUpdateDate(NSDate)
}

public class JSmartDataLoaderFields<Identifier, Result, DataLoadContext> {
    
    public typealias JAsyncBinderForIdentifier = (loadDataIdentifier: Identifier) -> AsyncTypes2<(DataRequestContext<DataLoadContext>, NSData), Result, NSError>.JAsyncBinder
    public typealias JCacheKeyForIdentifier    = (loadDataIdentifier: Identifier) -> String
    
    let loadDataIdentifier            : Identifier
    let dataLoaderForIdentifier       : AsyncTypes2<Identifier, (DataLoadContext, NSData), NSError>.JAsyncBinder
    let analyzerForData               : JAsyncBinderForIdentifier
    let cacheKeyForIdentifier         : JCacheKeyForIdentifier
    let doesNotIgnoreFreshDataLoadFail: Bool
    let cache                         : JAsyncRestKitCache
    let cacheDataLifeTimeInSeconds    : NSTimeInterval
    
    public init(
        loadDataIdentifier     : Identifier,
        dataLoaderForIdentifier: AsyncTypes2<Identifier, (DataLoadContext, NSData), NSError>.JAsyncBinder,
        analyzerForData        : JAsyncBinderForIdentifier,
        cacheKeyForIdentifier  : JCacheKeyForIdentifier,
        doesNotIgnoreFreshDataLoadFail: Bool,
        cache                  : JAsyncRestKitCache,
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

public func jSmartDataLoaderWithCache<Identifier, Result, DataLoadContext>(args: JSmartDataLoaderFields<Identifier, Result, DataLoadContext>) -> AsyncTypes<Result, NSError>.Async {
    
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
                              finishCallback  : AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.JDidFinishAsyncCallback?) -> JAsyncHandler in
        
        let loadCachedData: AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.Async = loadFreshCachedDataWithUpdateDate(
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
    
    let analyzer = { (response: (DataRequestContext<DataLoadContext>, NSData)) -> AsyncTypes<Result, NSError>.Async in
        
        let binder = analyzerForData(loadDataIdentifier: loadDataIdentifier)
        
        let analyzer = binder(response)
        
        let cacheBinder = { (analyzedData: Result) -> AsyncTypes<Result, NSError>.Async in
            
            let resultLoader: AsyncTypes<Result, NSError>.Async = asyncWithValue(analyzedData)
            
            switch response.0 {
            case .Outside:
                let loader = cache.loaderToSetData(response.1, forKey:key)
                return sequenceOfAsyncs(loader, resultLoader)
            case .CacheUpdateDate:
                return resultLoader
            }
        }
        
        return bindSequenceOfAsyncs(analyzer, cacheBinder)
    }
    
    return bindSequenceOfAsyncs(cachedDataLoader, analyzer)
}

internal class ErrorNoFreshData : Error {
    
    let cachedData: (NSDate, NSData)
    
    override class func jffErrorsDomain() -> String {
        return "com.just_for_fun.rest_kit_internal.library"
    }
    
    required init(cachedData: (NSDate, NSData)) {
        
        self.cachedData = cachedData
        super.init(description: "internal logic error (no fresh data)")
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private func dataLoaderWithCachedResultBinder<Identifier, DataLoadContext>(
    doesNotIgnoreFreshDataLoadFail: Bool,
    dataLoaderForIdentifier       : AsyncTypes2<Identifier, (DataLoadContext, NSData), NSError>.JAsyncBinder,
    loadDataIdentifier            : Identifier) -> AsyncTypes2<NSError, (DataRequestContext<DataLoadContext>, NSData), NSError>.JAsyncBinder
{
    return { (bindError: NSError) -> AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.Async in
        
        let finishCallbackHook = { (result: AsyncResult<(DataLoadContext, NSData), NSError>, doneCallback: AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.JDidFinishAsyncCallback?) -> () in
            
            switch result {
            case let .Success(v):
                //logs [ srvResponse_ logResponse ];
                let newResult = (DataRequestContext<DataLoadContext>.Outside(Box(v.value.0)), v.value.1)
                
                doneCallback?(result: AsyncResult.success(newResult))
            case let .Failure(error):
                //TODO test [bindError isKindOfClass:[JFFErrorNoFreshData class]] issue, here it can got - not data in cache error !!!
                if !doesNotIgnoreFreshDataLoadFail {
                    if let noFreshDataError = bindError as? ErrorNoFreshData {
                    
                        let newResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(noFreshDataError.cachedData.0), noFreshDataError.cachedData.1)
                        
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

private func loadFreshCachedDataWithUpdateDate<DataLoadContext>(
    key: String,
    cachedDataLoader: AsyncTypes<(NSDate, NSData), NSError>.Async,
    cacheDataLifeTimeInSeconds: NSTimeInterval) -> AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.Async
{
    let validateByDateResultBinder = { (cachedData: (NSDate, NSData)) -> AsyncTypes<(DataRequestContext<DataLoadContext>, NSData), NSError>.Async in
        
        let newDate = cachedData.0.dateByAddingTimeInterval(cacheDataLifeTimeInSeconds)
        if newDate.compare(NSDate()) == NSComparisonResult.OrderedDescending {
            
            let cachedResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(cachedData.0), cachedData.1)
            return asyncWithValue(cachedResult)
        }
        
        let error = ErrorNoFreshData(cachedData: cachedData)
        return asyncWithError(error)
    }
    
    return bindSequenceOfAsyncs(cachedDataLoader, validateByDateResultBinder)
}
