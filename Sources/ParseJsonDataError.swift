//
//  ParseJsonDataError.swift
//  iAsync_restkit
//
//  Created by Gorbenko Vladimir on 01.09.15.
//  Copyright © 2015 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_utils

final public class ParseJsonDataError : UtilsError {

    let data     : Data
    let jsonError: NSError
    let context  : CustomStringConvertible

    required public init(
        data     : Data,
        jsonError: NSError,
        context  : CustomStringConvertible) {

        self.data      = data
        self.jsonError = jsonError
        self.context   = context
        super.init(description: "ParseJsonDataError")
    }

    open override var localizedDescription: String {
        return "ParseJsonDataError: Parse Json Error: \(jsonError) response: \(data.toString()) context:\(context)"
    }

    override open var canRepeatError: Bool {

        return true
    }
}
