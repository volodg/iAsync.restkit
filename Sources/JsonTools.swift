//
//  JsonTools.swift
//  iAsync_restkit
//
//  Created by Gorbenko Vladimir on 01.09.15.
//  Copyright © 2015 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils
import iAsync_reactiveKit

import enum ReactiveKit.Result

public class JsonParserError : UtilsError {

    override open var canRepeatError: Bool {

        return true
    }
}

public extension AsyncStreamType where ValueT == Data, ErrorT == ErrorWithContext {

    func toJson() -> AsyncStream<Any, AnyObject, ErrorWithContext> {

        let stream = self.mapNext2AnyObject()
        return stream.flatMap { JsonTools.jsonStream(forData: $0) }
    }
}

public struct JsonTools {

    public static func jsonStream(forData data: Data, context: CustomStringConvertible? = nil) -> AsyncStream<Any, AnyObject, ErrorWithContext> {

        return asyncStreamWithJob { progress -> Result<Any, ErrorWithContext> in

            do {
                let jsonObj = try JSONSerialization.jsonObject(with: data as Data, options: [.allowFragments])
                return .success(jsonObj)
            } catch let error as NSError {
                let resError = ParseJsonDataError(data: data, jsonError: error, context: context ?? "")
                let contextError = ErrorWithContext(utilsError: resError, context: #function)
                return .failure(contextError)
            } catch {
                let contextError = ErrorWithContext(utilsError: JsonParserError(description: "JsonTools.jsonStream: unexpected system state"), context: #function)
                return .failure(contextError)
            }
        }
    }
}
