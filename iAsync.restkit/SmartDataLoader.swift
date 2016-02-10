//
//  SmartDataLoader.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils
import iAsync_reactiveKit

import ReactiveKit

public enum DataRequestContext<DataLoadContext> {

    case Outside(DataLoadContext)
    case CacheUpdateDate(NSDate)
}

final public class SmartDataLoaderFields<Identifier, Result, DataLoadContext> {

    public typealias AnalyzerType = (DataRequestContext<DataLoadContext>, NSData) -> AsyncStream<Result, AnyObject, NSError>

    let loadDataIdentifier        : Identifier
    let dataLoader                : AsyncStream<(DataLoadContext, NSData), AnyObject, NSError>
    let analyzerForData           : AnalyzerType
    let cacheKey                  : String
    let ignoreFreshDataLoadFail   : Bool
    let cache                     : AsyncRestKitCache
    let cacheDataLifeTimeInSeconds: NSTimeInterval

    public init(
        loadDataIdentifier        : Identifier,
        dataLoader                : AsyncStream<(DataLoadContext, NSData), AnyObject, NSError>,
        analyzerForData           : AnalyzerType,
        cacheKey                  : String,
        ignoreFreshDataLoadFail   : Bool,
        cache                     : AsyncRestKitCache,
        cacheDataLifeTimeInSeconds: NSTimeInterval) {

        self.loadDataIdentifier         = loadDataIdentifier
        self.dataLoader                 = dataLoader
        self.analyzerForData            = analyzerForData
        self.cacheKey                   = cacheKey
        self.ignoreFreshDataLoadFail    = ignoreFreshDataLoadFail
        self.cache                      = cache
        self.cacheDataLifeTimeInSeconds = cacheDataLifeTimeInSeconds
    }
}

public func jSmartDataLoaderWithCache<Identifier, Result, DataLoadContext>(args: SmartDataLoaderFields<Identifier, Result, DataLoadContext>) -> AsyncStream<Result, AnyObject, NSError> {

    let loadDataIdentifier         = args.loadDataIdentifier
    let dataLoader                 = args.dataLoader
    let analyzerForData            = args.analyzerForData
    let cache                      = args.cache
    let cacheKey                   = args.cacheKey
    let cacheDataLifeTimeInSeconds = args.cacheDataLifeTimeInSeconds
    let ignoreFreshDataLoadFail    = args.ignoreFreshDataLoadFail

    typealias StreamTT = AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError>
    let cachedDataLoader: StreamTT = create { observer in

        let loadCachedData: AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> = loadFreshCachedDataWithUpdateDate(
            cacheKey,
            cachedDataLoader          : cache.cachedDataLoaderForKey(cacheKey),
            cacheDataLifeTimeInSeconds: cacheDataLifeTimeInSeconds)

        let dataLoaderBinder = dataLoaderWithCachedResultBinder(
            ignoreFreshDataLoadFail,
            dataLoader        : dataLoader,
            loadDataIdentifier: loadDataIdentifier)

        return loadCachedData.flatMapError { dataLoaderBinder($0) }.observe(observer: observer)
    }

    let analyzer = { (response: (DataRequestContext<DataLoadContext>, NSData)) -> AsyncStream<Result, AnyObject, NSError> in

        let analyzer = analyzerForData(response)

        let cacheBinder = { (analyzedData: Result) -> AsyncStream<Result, AnyObject, NSError> in

            let resultLoader = AsyncStream<Result, AnyObject, NSError>.succeeded(with: analyzedData)

            switch response.0 {
            case .Outside:
                let loader = cache.loaderToSetData(response.1, forKey:cacheKey)
                return loader.flatMap { resultLoader }
            case .CacheUpdateDate:
                return resultLoader
            }
        }

        return analyzer.flatMap(AsyncStreamFlatMapStrategy.Latest, transform: { cacheBinder($0) })
    }

    return cachedDataLoader.flatMap(analyzer)
}

final internal class ErrorNoFreshData : Error {

    let cachedData: (date: NSDate, data: NSData)

    override class func iAsyncErrorsDomain() -> String {
        return "com.just_for_fun.rest_kit_internal.library"
    }

    required init(cachedData: (date: NSDate, data: NSData)) {

        self.cachedData = cachedData
        super.init(description: "internal logic error (no fresh data)")
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private func dataLoaderWithCachedResultBinder<Identifier, DataLoadContext>(
    ignoreFreshDataLoadFail: Bool,
    dataLoader             : AsyncStream<(DataLoadContext, NSData), AnyObject, NSError>,
    loadDataIdentifier     : Identifier) -> NSError -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError>
{
    return { (bindError: NSError) -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> in

        let dataLoader = dataLoader.map({ value -> (DataRequestContext<DataLoadContext>, NSData) in

            let newResult = (DataRequestContext<DataLoadContext>.Outside(value.0), value.1)
            return newResult
        }).tryMapError({ error -> Result<(DataRequestContext<DataLoadContext>, NSData), NSError> in

            if error is AsyncInterruptedError {
                return .Failure(error)
            }

            //TODO test [bindError isKindOfClass:[JFFErrorNoFreshData class]] issue, here it can got - not data in cache error !!!
            if ignoreFreshDataLoadFail {
                if let noFreshDataError = bindError as? ErrorNoFreshData {

                    let newResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(noFreshDataError.cachedData.0), noFreshDataError.cachedData.1)

                    return .Success(newResult)
                }
            }

            return .Failure(error)
        })

        return dataLoader
    }
}

private func loadFreshCachedDataWithUpdateDate<DataLoadContext>(
    key: String,
    cachedDataLoader: AsyncStream<(date: NSDate, data: NSData), AnyObject, NSError>,
    cacheDataLifeTimeInSeconds: NSTimeInterval) -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> {

    let validateByDateResultBinder = { (cachedData: (date: NSDate, data: NSData)) -> Result<(DataRequestContext<DataLoadContext>, NSData), NSError> in

        let newDate = cachedData.0.dateByAddingTimeInterval(cacheDataLifeTimeInSeconds)
        if newDate.compare(NSDate()) == .OrderedDescending {

            let cachedResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(cachedData.0), cachedData.1)
            return .Success(cachedResult)
        }

        let error = ErrorNoFreshData(cachedData: cachedData)
        return .Failure(error)
    }

    return cachedDataLoader.tryMap(validateByDateResultBinder)
}
