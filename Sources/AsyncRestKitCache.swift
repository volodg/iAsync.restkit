//
//  AsyncRestKitCache.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright © 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import struct iAsync_reactiveKit.AsyncStream
import struct iAsync_utils.ErrorWithContext

public protocol AsyncRestKitCache {

    func loaderToSet(data: Data, forKey key: String) -> AsyncStream<Void, Any, ErrorWithContext>

    func cachedDataStreamFor(key: String) -> AsyncStream<(date: Date, data: Data), Any, ErrorWithContext>
}
