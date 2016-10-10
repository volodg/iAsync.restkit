//
//  SmartDataStream.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright © 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils
import iAsync_reactiveKit

import enum ReactiveKit.Result

public enum DataRequestContext<DataLoadContext> {

    case outside(DataLoadContext)
    case cacheUpdateDate(Date)
}

public enum CacheStrategy {

    case networkFirst
    case cacheFirst(TimeInterval?)
}

final public class SmartDataStreamFields<Result, DataLoadContext> {

    public typealias AnalyzerType = (DataRequestContext<DataLoadContext>, Data) -> AsyncStream<Result, AnyObject, ErrorWithContext>

    let dataStream     : AsyncStream<(DataLoadContext, Data), AnyObject, ErrorWithContext>
    let analyzerForData: AnalyzerType
    let cacheKey       : String
    let cache          : AsyncRestKitCache
    let strategy       : CacheStrategy

    public init(
        dataStream     : AsyncStream<(DataLoadContext, Data), AnyObject, ErrorWithContext>,
        analyzerForData: @escaping AnalyzerType,
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

public func jSmartDataStreamWith<Result, DataLoadContext>(cacheArgs: SmartDataStreamFields<Result, DataLoadContext>) -> AsyncStream<Result, AnyObject, ErrorWithContext> {

    let dataStream      = cacheArgs.dataStream
    let analyzerForData = cacheArgs.analyzerForData
    let cache           = cacheArgs.cache
    let cacheKey        = cacheArgs.cacheKey
    let strategy        = cacheArgs.strategy

    let cachedDataStream: AsyncStream<(DataRequestContext<DataLoadContext>, Data), AnyObject, ErrorWithContext> =
        loadFreshCachedDataWithUpdateDate(cache.cachedDataStreamFor(key: cacheKey), strategy: strategy)

    switch cacheArgs.strategy {
    case .networkFirst:
        return dataStream.flatMap { contextData -> AsyncStream<Result, AnyObject, ErrorWithContext> in

            let context = contextData.0
            let data    = contextData.1

            return analyzerForData(DataRequestContext.outside(context), data).flatMap { result -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                let stream = cache.loaderToSet(data: data, forKey:cacheKey)
                return stream.map { result }
            }
        }.flatMapError { error -> AsyncStream<Result, AnyObject, ErrorWithContext> in
            return cachedDataStream.flatMap(analyzerForData).mapError { _ in error }
        }
    case .cacheFirst:

        typealias StreamTT = AsyncStream<(DataRequestContext<DataLoadContext>, Data), AnyObject, ErrorWithContext>
        let cachedDataStream: StreamTT = AsyncStream { observer in

            return cachedDataStream.flatMapError { _ -> AsyncStream<(DataRequestContext<DataLoadContext>, Data), AnyObject, ErrorWithContext> in

                return dataStream.map { value -> (DataRequestContext<DataLoadContext>, Data) in

                    let newResult = (DataRequestContext<DataLoadContext>.outside(value.0), value.1)
                    return newResult
                }
            }.observe(observer)
        }

        let analyzer = { (response: (DataRequestContext<DataLoadContext>, Data)) -> AsyncStream<Result, AnyObject, ErrorWithContext> in

            let analyzer = analyzerForData(response.0, response.1)

            let stream = analyzer.flatMap { analyzedData -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                switch response.0 {
                case .outside:
                    let stream = cache.loaderToSet(data: response.1, forKey:cacheKey)
                    return stream.map { analyzedData }
                case .cacheUpdateDate:
                    return AsyncStream.succeeded(with: analyzedData)
                }
            }

            return stream.flatMapError { error -> AsyncStream<Result, AnyObject, ErrorWithContext> in

                switch response.0 {
                case .outside:
                    return cachedDataStream.flatMap(analyzerForData).mapError { _ in error }
                case .cacheUpdateDate:
                    return AsyncStream.failed(with: error)
                }
            }
        }

        return cachedDataStream.flatMap(analyzer)
    }
}

final internal class ErrorNoFreshData : UtilsError {

    let cachedData: (date: Date, data: Data)

    override class func iAsyncErrorsDomain() -> String {
        return "com.just_for_fun.rest_kit_internal.library"
    }

    required init(cachedData: (date: Date, data: Data)) {

        self.cachedData = cachedData
        super.init(description: "internal logic error (no fresh data)")
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private func loadFreshCachedDataWithUpdateDate<DataLoadContext>(
    _ cachedDataSteam: AsyncStream<(date: Date, data: Data), AnyObject, ErrorWithContext>,
    strategy       : CacheStrategy) -> AsyncStream<(DataRequestContext<DataLoadContext>, Data), AnyObject, ErrorWithContext> {

    let validateByDateResultBinder = { (cachedData: (date: Date, data: Data)) -> Result<(DataRequestContext<DataLoadContext>, Data), ErrorWithContext> in

        let cachedResult = (DataRequestContext<DataLoadContext>.cacheUpdateDate(cachedData.0), cachedData.1)

        switch strategy {
        case .networkFirst:
            return .success(cachedResult)
        case .cacheFirst(let ttl):
            guard let ttl = ttl else { return .success(cachedResult) }

            let newDate = cachedData.0.addingTimeInterval(ttl)
            if newDate.compare(Date()) == .orderedDescending {

                let cachedResult = (DataRequestContext<DataLoadContext>.cacheUpdateDate(cachedData.0), cachedData.1)
                return .success(cachedResult)
            }

            let error = ErrorNoFreshData(cachedData: cachedData)
            let contextError = ErrorWithContext(error: error, context: #function)
            return .failure(contextError)
        }
    }

    return cachedDataSteam.tryMap(validateByDateResultBinder)
}
