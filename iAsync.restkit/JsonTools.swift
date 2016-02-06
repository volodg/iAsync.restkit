//
//  JsonTools.swift
//  iAsync_restkit
//
//  Created by Gorbenko Vladimir on 01.09.15.
//  Copyright (c) 2015 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_async
import iAsync_utils
import iAsync_reactiveKit

import ReactiveKit

public struct JsonTools {

    public static func jsonLoader(data: NSData, context: CustomStringConvertible) -> AsyncTypes<AnyObject, NSError>.Async {

        return asyncStreamWithJob { (progress: AnyObject -> Void) -> Result<AnyObject, NSError> in

            do {
                let jsonObj = try NSJSONSerialization.JSONObjectWithData(data, options: [.AllowFragments])
                return .Success(jsonObj)
            } catch let error as NSError {
                let resError = ParseJsonDataError(data: data, jsonError: error, context: context)
                return .Failure(resError)
            } catch {
                return .Failure(Error(description: "unexpected system state 2"))
            }
        }.toAsync()
    }
}
