//
//  ParseJsonDataError.swift
//  iAsync_restkit
//
//  Created by Gorbenko Vladimir on 01.09.15.
//  Copyright (c) 2015 EmbeddedSources. All rights reserved.
//

import Foundation

final public class ParseJsonDataError : UtilsError {

    let data     : NSData
    let jsonError: NSError
    let context  : CustomStringConvertible

    required public init(
        data     : NSData,
        jsonError: NSError,
        context  : CustomStringConvertible) {

        self.data      = data
        self.jsonError = jsonError
        self.context   = context
        super.init(description: "ParseJsonDataError")
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var localizedDescription: String {
        return "ParseJsonDataError: Parse Json Error: \(jsonError) response: \(data.toString()) context:\(context)"
    }
}
