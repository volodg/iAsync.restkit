//
//  JAsyncRestKitCache.swift
//  JRestKit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_async

public protocol JAsyncRestKitCache {
    
    func loaderToSetData(data: NSData, forKey key: String) -> AsyncTypes<NSNull, NSError>.Async
    
    func cachedDataLoaderForKey(key: String) -> AsyncTypes<JRestKitCachedData, NSError>.Async
}
