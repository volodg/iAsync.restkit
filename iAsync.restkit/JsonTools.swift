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

import ReactiveKit_old//???

public class JsonParserError : UtilsError {}

public extension AsyncStreamType where Self.Value == NSData, Self.Error == ErrorWithContext {

    @warn_unused_result
    func toJson() -> AsyncStream<AnyObject, AnyObject, ErrorWithContext> {

        let stream = self.mapNext2AnyObject()
        return stream.flatMap { JsonTools.jsonStream($0) }
    }
}

public struct JsonTools {

    @warn_unused_result
    public static func jsonStream(data: NSData, context: CustomStringConvertible? = nil) -> AsyncStream<AnyObject, AnyObject, ErrorWithContext> {

        return asyncStreamWithJob { progress -> Result<AnyObject, ErrorWithContext> in

            do {
                let jsonObj = try NSJSONSerialization.JSONObjectWithData(data, options: [.AllowFragments])
                return .Success(jsonObj)
            } catch let error as NSError {
                let resError = ParseJsonDataError(data: data, jsonError: error, context: context ?? "")
                let contextError = ErrorWithContext(error: resError, context: #function)
                return .Failure(contextError)
            } catch {
                let contextError = ErrorWithContext(error: JsonParserError(description: "JsonTools.jsonStream: unexpected system state"), context: #function)
                return .Failure(contextError)
            }
        }
    }
}
