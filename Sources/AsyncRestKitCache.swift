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

    func loaderToSetData(_ data: Data, forKey key: String) -> AsyncStream<Void, AnyObject, ErrorWithContext>

    func cachedDataStreamForKey(_ key: String) -> AsyncStream<(date: Date, data: Data), AnyObject, ErrorWithContext>
}
