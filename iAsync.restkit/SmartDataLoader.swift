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

public enum CacheStrategy {

    case NetworkFirst
    case CacheFirst(NSTimeInterval?)
}

final public class SmartDataLoaderFields<Result, DataLoadContext> {

    public typealias AnalyzerType = (DataRequestContext<DataLoadContext>, NSData) -> AsyncStream<Result, AnyObject, NSError>

    let dataStream     : AsyncStream<(DataLoadContext, NSData), AnyObject, NSError>
    let analyzerForData: AnalyzerType
    let cacheKey       : String
    let cache          : AsyncRestKitCache
    let strategy       : CacheStrategy

    public init(
        dataStream     : AsyncStream<(DataLoadContext, NSData), AnyObject, NSError>,
        analyzerForData: AnalyzerType,
        cacheKey       : String,
        cache          : AsyncRestKitCache,
        strategy       : CacheStrategy) {

        self.dataStream      = dataStream
        self.analyzerForData = analyzerForData
        self.cacheKey        = cacheKey
        self.cache           = cache
        self.strategy        = strategy
    }
}

public func jSmartDataLoaderWithCache<Result, DataLoadContext>(args: SmartDataLoaderFields<Result, DataLoadContext>) -> AsyncStream<Result, AnyObject, NSError> {

    let dataStream      = args.dataStream
    let analyzerForData = args.analyzerForData
    let cache           = args.cache
    let cacheKey        = args.cacheKey
    let strategy        = args.strategy

    let cachedDataStream: AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> =
        loadFreshCachedDataWithUpdateDate(cache.cachedDataLoaderForKey(cacheKey), strategy: strategy)

    switch args.strategy {
    case .NetworkFirst:
        return dataStream.flatMap { (context, data) -> AsyncStream<Result, AnyObject, NSError> in
            return analyzerForData(DataRequestContext.Outside(context), data).flatMap { result -> AsyncStream<Result, AnyObject, NSError> in

                let stream = cache.loaderToSetData(data, forKey:cacheKey)
                return stream.map { result }
            }
        }.flatMapError { _ -> AsyncStream<Result, AnyObject, NSError> in
            return cachedDataStream.flatMap(analyzerForData)
        }
    case .CacheFirst:

        typealias StreamTT = AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError>
        let cachedDataLoader: StreamTT = create { observer in

            return cachedDataStream.flatMapError { error -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> in

                return dataStream.map { value -> (DataRequestContext<DataLoadContext>, NSData) in

                    let newResult = (DataRequestContext<DataLoadContext>.Outside(value.0), value.1)
                    return newResult
                }
            }.observe(observer: observer)
        }

        let analyzer = { (response: (DataRequestContext<DataLoadContext>, NSData)) -> AsyncStream<Result, AnyObject, NSError> in

            let analyzer = analyzerForData(response)

            let cacheBinder = { (analyzedData: Result) -> AsyncStream<Result, AnyObject, NSError> in

                switch response.0 {
                case .Outside:
                    let stream = cache.loaderToSetData(response.1, forKey:cacheKey)
                    return stream.map { analyzedData }
                case .CacheUpdateDate:
                    return AsyncStream.succeeded(with: analyzedData)
                }
            }

            let stream = analyzer.flatMap { cacheBinder($0) }

            return stream.flatMapError { error -> AsyncStream<Result, AnyObject, NSError> in

                switch response.0 {
                case .Outside:
                    return cachedDataStream.flatMap(analyzerForData)
                case .CacheUpdateDate:
                    return AsyncStream.failed(with: error)
                }
            }
        }

        return cachedDataLoader.flatMap(analyzer)
    }
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

private func loadFreshCachedDataWithUpdateDate<DataLoadContext>(
    cachedDataSteam: AsyncStream<(date: NSDate, data: NSData), AnyObject, NSError>,
    strategy       : CacheStrategy) -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, NSError> {
        
    let validateByDateResultBinder = { (cachedData: (date: NSDate, data: NSData)) -> Result<(DataRequestContext<DataLoadContext>, NSData), NSError> in

        let cachedResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(cachedData.0), cachedData.1)

        switch strategy {
        case .NetworkFirst:
            return .Success(cachedResult)
        case .CacheFirst(let ttl):
            guard let ttl = ttl else { return .Success(cachedResult) }

            let newDate = cachedData.0.dateByAddingTimeInterval(ttl)
            if newDate.compare(NSDate()) == .OrderedDescending {

                let cachedResult = (DataRequestContext<DataLoadContext>.CacheUpdateDate(cachedData.0), cachedData.1)
                return .Success(cachedResult)
            }

            let error = ErrorNoFreshData(cachedData: cachedData)
            return .Failure(error)
        }
    }

    return cachedDataSteam.tryMap(validateByDateResultBinder)
}
