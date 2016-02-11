//
//  JsonTools.swift
//  iAsync_restkit
//
//  Created by Gorbenko Vladimir on 01.09.15.
//  Copyright (c) 2015 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils
import iAsync_reactiveKit

import ReactiveKit

public extension AsyncStreamType where Self.Value == NSData, Self.Error == NSError {

    func toJson() -> AsyncStream<AnyObject, AnyObject, NSError> {

        let stream = self.mapNext { _ in NSNull() as AnyObject }
        return stream.flatMap { JsonTools.jsonLoader($0) }
    }
}

public struct JsonTools {

    public static func jsonLoader(data: NSData, context: CustomStringConvertible? = nil) -> AsyncStream<AnyObject, AnyObject, NSError> {

        return asyncStreamWithJob { (progress: AnyObject -> Void) -> Result<AnyObject, NSError> in

            do {
                let jsonObj = try NSJSONSerialization.JSONObjectWithData(data, options: [.AllowFragments])
                return .Success(jsonObj)
            } catch let error as NSError {
                let resError = ParseJsonDataError(data: data, jsonError: error, context: context ?? "")
                return .Failure(resError)
            } catch {
                return .Failure(Error(description: "unexpected system state 2"))
            }
        }
    }
}
