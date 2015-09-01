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

public struct JsonTools {
    
    public static func jsonLoader(data: NSData, context: Printable) -> AsyncTypes<AnyObject, NSError>.Async {
        
        return asyncWithSyncOperation({ () -> AsyncResult<AnyObject, NSError> in
            
            var error: NSError?
            
            let jsonObj: AnyObject! = NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments, error: &error)
            //println("error: \(error)")
            
            if let error = error {
                
                let resError = ParseJsonDataError(data: data, jsonError: error, context: context)
                return AsyncResult.failure(resError)
            }
            
            return AsyncResult.success(jsonObj)
        })
    }
}
