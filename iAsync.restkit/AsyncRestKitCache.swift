//
//  AsyncRestKitCache.swift
//  iAsync_restkit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_async

public protocol AsyncRestKitCache {
    
    func loaderToSetData(data: NSData, forKey key: String) -> AsyncTypes<Void, NSError>.Async
    
    func cachedDataLoaderForKey(key: String) -> AsyncTypes<(NSDate, NSData), NSError>.Async
}
