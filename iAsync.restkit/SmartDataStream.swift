//
//  SmartDataStream.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils
import struct iAsync_reactiveKit.AsyncStream
import func iAsync_reactiveKit.create

import ReactiveKit

public enum DataRequestContext<DataLoadContext> {

    case Outside(DataLoadContext)
    case CacheUpdateDate(NSDate)
}

public enum CacheStrategy {

    case NetworkFirst
    case CacheFirst(NSTimeInterval?)
}

final public class SmartDataStreamFields<Result, DataLoadContext> {

    public typealias AnalyzerType = (DataRequestContext<DataLoadContext>, NSData) -> AsyncStream<Result, AnyObject, ErrorWithContext>

    let dataStream     : AsyncStream<(DataLoadContext, NSData), AnyObject, ErrorWithContext>
    let analyzerForData: AnalyzerType
    let cacheKey       : String
    let cache          : AsyncRestKitCache
    let strategy       : CacheStrategy

    public init(
        dataStream     : AsyncStream<(DataLoadContext, NSData), AnyObject, ErrorWithContext>,
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

public func jSmartDataStreamWithCache<Result, DataLoadContext>(args: SmartDataStreamFields<Result, DataLoadContext>) -> AsyncStream<Result, AnyObject, ErrorWithContext> {

    let dataStream      = args.dataStream
    let analyzerForData = args.analyzerForData
    let cache           = args.cache
    let cacheKey        = args.cacheKey
    let strategy        = args.strategy

    let cachedDataStream: AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, ErrorWithContext> =
        loadFreshCachedDataWithUpdateDate(cache.cachedDataStreamForKey(cacheKey), strategy: strategy)

    switch args.strategy {
    case .NetworkFirst:
        return dataStream.flatMap { (context, data) -> AsyncStream<Result, AnyObject, ErrorWithContext> in
            return analyzerForData(DataRequestContext.Outside(context), data).flatMap { result -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                let stream = cache.loaderToSetData(data, forKey:cacheKey)
                return stream.map { result }
            }
        }.flatMapError { error -> AsyncStream<Result, AnyObject, ErrorWithContext> in
            return cachedDataStream.flatMap(analyzerForData).mapError { _ in error }
        }
    case .CacheFirst:

        typealias StreamTT = AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, ErrorWithContext>
        let cachedDataStream: StreamTT = create { observer in

            return cachedDataStream.flatMapError { _ -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, ErrorWithContext> in

                return dataStream.map { value -> (DataRequestContext<DataLoadContext>, NSData) in

                    let newResult = (DataRequestContext<DataLoadContext>.Outside(value.0), value.1)
                    return newResult
                }
            }.observe(observer: observer)
        }

        let analyzer = { (response: (DataRequestContext<DataLoadContext>, NSData)) -> AsyncStream<Result, AnyObject, ErrorWithContext> in

            let analyzer = analyzerForData(response)

            let stream = analyzer.flatMap { analyzedData -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                switch response.0 {
                case .Outside:
                    let stream = cache.loaderToSetData(response.1, forKey:cacheKey)
                    return stream.map { analyzedData }
                case .CacheUpdateDate:
                    return AsyncStream.succeeded(with: analyzedData)
                }
            }

            return stream.flatMapError { error -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                switch response.0 {
                case .Outside:
                    return cachedDataStream.flatMap(analyzerForData).mapError { _ in error }
                case .CacheUpdateDate:
                    return AsyncStream.failed(with: error)
                }
            }
        }

        return cachedDataStream.flatMap(analyzer)
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
    cachedDataSteam: AsyncStream<(date: NSDate, data: NSData), AnyObject, ErrorWithContext>,
    strategy       : CacheStrategy) -> AsyncStream<(DataRequestContext<DataLoadContext>, NSData), AnyObject, ErrorWithContext> {

    let validateByDateResultBinder = { (cachedData: (date: NSDate, data: NSData)) -> Result<(DataRequestContext<DataLoadContext>, NSData), ErrorWithContext> in

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
            let contextError = ErrorWithContext(error: error, context: "loadFreshCachedDataWithUpdateDate.CacheFirst")
            return .Failure(contextError)
        }
    }

    return cachedDataSteam.tryMap(validateByDateResultBinder)
}
