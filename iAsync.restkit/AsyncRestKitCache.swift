//
//  AsyncRestKitCache.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import struct iAsync_reactiveKit.AsyncStream

public protocol AsyncRestKitCache {

    func loaderToSetData(data: NSData, forKey key: String) -> AsyncStream<Void, AnyObject, NSError>

    func cachedDataStreamForKey(key: String) -> AsyncStream<(date: NSDate, data: NSData), AnyObject, NSError>
}
